import Foundation
import Observation
import ActivityKit
import UIKit
import Combine

@Observable
@MainActor
final class GatewayClient {
    var isConnected = false
    private var disconnectGraceTask: Task<Void, Never>?
    private var suppressDisconnectHaptic = false
    var currentTask = "Waiting for instructions"
    var activeAgents: [AgentInfo] = []
    @ObservationIgnored
    @Published var activeSessions: [ActiveSession] = [] {
        didSet {
            activeSessionsSnapshot = activeSessions
        }
    }
    var activeSessionsSnapshot: [ActiveSession] = []
    var messages: [ChatMessage] = []
    var sessionUptime: TimeInterval = 0
    private var connectedAt: Date?
    var modelName: String = "—"
    var activeSubAgentCount: Int = 0
    var lastHeartbeat: Date?
    var connectionError: String?
    var sessionKey: String = "agent:main:main"
    
    // Thinking state — separated from final messages
    var isThinking = false
    var thinkingText: String = ""
    
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var gatewayURL: URL?
    private var authToken: String?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var uptimeTask: Task<Void, Never>?
    private var pendingRequests: [String: (Data?) -> Void] = [:]
    private var requestCounter = 0
    private var challengeNonce: String?
    private var currentStreamText: String = ""
    private var quickCommandCallback: ((String?) -> Void)?
    private var quickCommandWatchdog: Task<Void, Never>?
    private var quickCommandStreamText: String = ""
    private let iso8601Formatter = ISO8601DateFormatter()
    private let sessionDelegate = TailscaleTLSDelegate()
    private var storedPushToken: String? = UserDefaults.standard.string(forKey: "pushDeviceToken")
    private var activeSessionsTask: Task<Void, Never>? = nil
    
    // Live Activity management
    private var currentActivity: Activity<FrankActivityAttributes>?
    
    struct AgentInfo: Identifiable, Codable {
        let id: String
        let name: String
        let status: String
        let model: String?
    }
    
    enum SessionKind: String {
        case main, subagent, cron, group, other
    }
    
    struct ActiveSession: Identifiable, Equatable {
        let key: String
        let model: String
        let label: String
        let updatedAt: Date
        let lastMessage: String
        let isActive: Bool
        let kind: SessionKind
        let totalTokens: Int
        var id: String { key }
    }
    
    struct ChatMessage: Identifiable {
        let id: String
        let text: String
        let isFromUser: Bool
        let timestamp: Date
        var isStreaming: Bool = false
        var imageData: Data? = nil // JPEG data for sent images
    }
    
    // MARK: - Connection
    
    func configure(host: String, port: Int = 18789, token: String, useTailscaleServe: Bool = false) {
        let urlString: String
        if useTailscaleServe {
            // Tailscale Serve proxies HTTPS → local gateway, so use wss:// with no port
            urlString = "wss://\(host)"
        } else {
            urlString = "ws://\(host):\(port)"
        }
        gatewayURL = URL(string: urlString)
        authToken = token
    }
    
    func connect() {
        guard let url = gatewayURL else {
            connectionError = "No gateway URL configured"
            return
        }
        
        disconnect()
        connectionError = nil
        challengeNonce = nil
        
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        
        // Gateway requires an Origin header for WebSocket connections
        var request = URLRequest(url: url)
        // Use https:// origin for wss:// connections (standard WebSocket behavior)
        let origin = url.absoluteString
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()
        
        receiveMessage()
        // Don't send handshake yet — wait for connect.challenge event
    }
    
    func disconnect() {
        reconnectTask?.cancel()
        pingTask?.cancel()
        uptimeTask?.cancel()
        activeSessionsTask?.cancel()
        disconnectGraceTask?.cancel()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        connectedAt = nil
        sessionUptime = 0
        challengeNonce = nil
        pendingRequests.removeAll()
        activeSessions = []
        
        // End Live Activity
        endLiveActivity()
        
        // Add haptic feedback for disconnection (unless suppressed during auto-reconnect)
        if !suppressDisconnectHaptic {
            let warning = UINotificationFeedbackGenerator()
            warning.notificationOccurred(.warning)
        }
        syncToSharedState()
    }
    
    /// Sync current state to App Groups UserDefaults for widgets
    private func syncToSharedState() {
        let assistantMessages = messages.filter { !$0.isFromUser }
        let lastAssistantMessage = assistantMessages.last?.text.prefix(200).description ?? ""
        let messagesToday = assistantMessages.filter { Calendar.current.isDateInToday($0.timestamp) }.count
        let currentTaskStatus = isConnected ? "Connected - Ready" : "Disconnected"
        SharedStateWriter.update(
            isConnected: isConnected,
            currentTask: currentTaskStatus,
            modelName: modelName,
            subAgentCount: activeSubAgentCount,
            sessionUptime: sessionUptime,
            lastMessage: lastAssistantMessage,
            messagesToday: messagesToday
        )
    }
    
    func reconnectIfNeeded() {
        guard gatewayURL != nil else { return }
        if !isConnected {
            connect()
        }
    }
    
    // MARK: - OpenClaw Protocol
    
    private func sendConnectHandshake() {
        let instanceId = UUID().uuidString
        
        var authDict: [String: Any] = [:]
        if let token = authToken, !token.isEmpty {
            authDict["token"] = token
        }
        
        let params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": "openclaw-ios",
                "version": "1.0.0",
                "platform": "iOS",
                "mode": "webchat",
                "instanceId": instanceId
            ],
            "role": "operator",
            "scopes": ["operator.admin"],
            "caps": [],
            "auth": authDict,
            "userAgent": "Frank-iOS/1.0",
            "locale": Locale.current.identifier
        ]
        
        sendRequest(method: "connect", params: params) { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                if let data = response,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["ok"] as? Bool == true {
                    self.disconnectGraceTask?.cancel()
                    self.isConnected = true
                    if self.connectedAt == nil {
                        self.connectedAt = Date()  // Only reset uptime on fresh connect, not reconnect
                    }
                    self.suppressDisconnectHaptic = false
                    self.connectionError = nil
                    self.startPing()
                    self.startUptimeTimer()
                    self.addSystemMessage("Connected to OpenClaw gateway")
                    self.syncToSharedState()
                    // Load chat history
                    self.loadChatHistory()
                    self.fetchSessionStatus()
                    self.fetchActiveSessions()
                    self.startActiveSessionsPolling()
                    // Start Live Activity
                    self.startLiveActivity()
                    self.transmitStoredPushToken()
                    
                    // Add haptic feedback for connection
                    let success = UINotificationFeedbackGenerator()
                    success.notificationOccurred(.success)
                } else {
                    var errMsg = "Connect handshake failed"
                    if let data = response,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? [String: Any],
                       let msg = error["message"] as? String {
                        errMsg = msg
                    }
                    self.connectionError = errMsg
                    self.scheduleReconnect()
                }
            }
        }
    }
    
    private func sendRequest(method: String, params: [String: Any], completion: ((Data?) -> Void)? = nil) {
        requestCounter += 1
        let reqId = "ios-\(requestCounter)"
        
        let message: [String: Any] = [
            "type": "req",
            "id": reqId,
            "method": method,
            "params": params
        ]
        
        if let completion {
            pendingRequests[reqId] = completion
        }
        
        sendJSON(message)
    }
    
    // MARK: - Chat History
    
    private func loadChatHistory() {
        sendRequest(method: "chat.history", params: [
            "sessionKey": sessionKey,
            "limit": 50
        ]) { [weak self] response in
            Task { @MainActor in
                guard let self, let data = response,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = json["payload"] as? [String: Any],
                      let msgs = payload["messages"] as? [[String: Any]] else { return }
                
                var loaded: [ChatMessage] = []
                for msg in msgs {
                    let role = msg["role"] as? String ?? ""
                    let content = msg["content"]
                    let ts = msg["timestamp"] as? Double ?? Date().timeIntervalSince1970 * 1000
                    let text = self.extractText(from: content)
                    if !text.isEmpty {
                        loaded.append(ChatMessage(
                            id: UUID().uuidString,
                            text: text,
                            isFromUser: role == "user",
                            timestamp: Date(timeIntervalSince1970: ts / 1000)
                        ))
                    }
                }
                self.messages = loaded
                self.syncToSharedState()
            }
        }
    }
    
    private func extractText(from content: Any?) -> String {
        if let str = content as? String { return str }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { item -> String? in
                guard item["type"] as? String == "text" else { return nil }
                return item["text"] as? String
            }.joined(separator: "\n")
        }
        return ""
    }
    
    // MARK: - Calendar Sync
    
    func syncCalendar(events: [CalendarSyncEvent]) {
        let eventsData = events.map { event -> [String: Any] in
            [
                "title": event.title,
                "start": event.start,
                "end": event.end,
                "calendar": event.calendar,
                "isAllDay": event.isAllDay,
                "location": event.location ?? ""
            ]
        }
        
        // Send as a system-level message that Frank can parse
        let formatter = ISO8601DateFormatter()
        var lines = ["[CALENDAR_SYNC]"]
        for event in events {
            let allDay = event.isAllDay ? " (All Day)" : ""
            let loc = event.location.map { " @ \($0)" } ?? ""
            lines.append("• \(event.start) - \(event.end)\(allDay): \(event.title) [\(event.calendar)]\(loc)")
        }
        lines.append("[/CALENDAR_SYNC]")
        
        // Send to a dedicated calendar sync "session" via chat
        sendRequest(method: "chat.send", params: [
            "sessionKey": sessionKey,
            "message": lines.joined(separator: "\n"),
            "deliver": false,
            "idempotencyKey": "cal-sync-\(Int(Date().timeIntervalSince1970))",
            "silent": true
        ])
    }
    
    struct CalendarSyncEvent {
        let title: String
        let start: String
        let end: String
        let calendar: String
        let isAllDay: Bool
        let location: String?
    }
    
    // MARK: - Push Notifications

    func sendPushToken(_ token: String) {
        storedPushToken = token
        UserDefaults.standard.set(token, forKey: "pushDeviceToken")
        transmitStoredPushToken()
    }

    private func transmitStoredPushToken() {
        guard isConnected, let token = storedPushToken else { return }
        sendRequest(method: "device.registerPush", params: [
            "token": token,
            "platform": "apns"
        ])
    }

    // MARK: - Messaging
    
    func reloadHistory() {
        loadChatHistory()
    }
    
    func sendChatWithImage(text: String, image: UIImage) {
        // Aggressively resize — max 512px on longest side, quality 0.5
        let maxSize: CGFloat = 512
        var img = image
        if max(img.size.width, img.size.height) > maxSize {
            let scale = maxSize / max(img.size.width, img.size.height)
            let newSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            img = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        
        guard let jpegData = img.jpegData(compressionQuality: 0.5) else { return }
        let base64 = jpegData.base64EncodedString()
        
        let msgId = UUID().uuidString
        let msg = ChatMessage(id: msgId, text: text, isFromUser: true, timestamp: Date(), imageData: jpegData)
        messages.append(msg)
        syncToSharedState()
        
        // Send as multipart content with image
        let content: [[String: Any]] = [
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]],
            ["type": "text", "text": text]
        ]
        
        sendRequest(method: "chat.send", params: [
            "sessionKey": sessionKey,
            "message": content,
            "deliver": false,
            "idempotencyKey": msgId
        ])
    }
    
    func sendChat(_ text: String) {
        let msgId = UUID().uuidString
        let msg = ChatMessage(id: msgId, text: text, isFromUser: true, timestamp: Date())
        messages.append(msg)
        syncToSharedState()
        
        sendRequest(method: "chat.send", params: [
            "sessionKey": sessionKey,
            "message": text,
            "deliver": false,
            "idempotencyKey": msgId
        ])
    }
    
    /// Send a quick command to the gateway without polluting main chat.
    /// Sends normally but captures the response by tracking message count.
    func sendQuickCommand(prompt: String, commandId: String, completion: @escaping (String?) -> Void) {
        // Cancel any existing quick command
        quickCommandWatchdog?.cancel()
        quickCommandCallback = nil
        quickCommandStreamText = ""
        
        // Store callback
        quickCommandCallback = { response in
            completion(response)
        }
        
        // Watchdog timeout
        quickCommandWatchdog = Task {
            try? await Task.sleep(for: .seconds(45))
            if !Task.isCancelled {
                let cb = self.quickCommandCallback
                self.quickCommandCallback = nil
                self.quickCommandStreamText = ""
                cb?(nil)
            }
        }
        
        // Send without adding to messages array
        sendRequest(method: "chat.send", params: [
            "sessionKey": sessionKey,
            "message": prompt,
            "deliver": false,
            "idempotencyKey": "qc-\(commandId)-\(Int(Date().timeIntervalSince1970))"
        ])
    }
    
    private func addSystemMessage(_ text: String) {
        let msg = ChatMessage(id: UUID().uuidString, text: text, isFromUser: false, timestamp: Date())
        messages.append(msg)
        syncToSharedState()
    }
    
    // MARK: - Live Activities
    
    private func startLiveActivity() {
        // Only start if ActivityKit is available and we're not already running an activity
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              currentActivity == nil else { return }
        
        let attributes = FrankActivityAttributes()
        let contentState = FrankActivityAttributes.ContentState(
            frankStatus: isConnected ? "Online" : "Offline",
            currentTask: currentTask,
            modelName: modelName,
            lastMessage: messages.last?.text.prefix(50).description ?? "",
            isConnected: isConnected,
            subAgentCount: activeSubAgentCount,
            uptime: sessionUptime,
            lastUpdated: Date()
        )
        
        do {
            currentActivity = try Activity<FrankActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: Date())),
                pushType: nil
            )
        } catch {
            print("[GatewayClient] Failed to start Live Activity: \(error)")
        }
    }
    
    private func updateLiveActivity() {
        guard let activity = currentActivity else { return }
        
        let contentState = FrankActivityAttributes.ContentState(
            frankStatus: isConnected ? "Online" : "Offline",
            currentTask: currentTask,
            modelName: modelName,
            lastMessage: messages.last?.text.prefix(50).description ?? "",
            isConnected: isConnected,
            subAgentCount: activeSubAgentCount,
            uptime: sessionUptime,
            lastUpdated: Date()
        )
        
        Task {
            await activity.update(.init(
                state: contentState,
                staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ))
        }
    }
    
    private func endLiveActivity() {
        guard let activity = currentActivity else { return }
        
        Task {
            await activity.end(.init(
                state: FrankActivityAttributes.ContentState(
                    frankStatus: "Offline",
                    currentTask: "Disconnected",
                    modelName: modelName,
                    lastMessage: "Session ended",
                    isConnected: false,
                    subAgentCount: 0,
                    uptime: sessionUptime,
                    lastUpdated: Date()
                ),
                staleDate: Date()
            ))
        }
        currentActivity = nil
    }
    
    // MARK: - Private
    
    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(str)) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.connectionError = error.localizedDescription
                }
            }
        }
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    self.receiveMessage()
                case .failure(let error):
                    self.connectionError = error.localizedDescription
                    self.handleTransientDisconnect()
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        lastHeartbeat = Date()
        
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        let type = json["type"] as? String ?? ""
        
        switch type {
        case "res":
            // Response to a request
            if let reqId = json["id"] as? String, let handler = pendingRequests.removeValue(forKey: reqId) {
                handler(data)
            }
            
        case "event":
            handleEvent(json)
            
        case "ping":
            sendJSON(["type": "pong"])
            
        default:
            #if DEBUG
            print("[GatewayClient] Unknown type: \(type)")
            #endif
        }
    }
    
    private func handleEvent(_ json: [String: Any]) {
        let event = json["event"] as? String ?? ""
        let payload = json["payload"] as? [String: Any]
        
        switch event {
        case "connect.challenge":
            // Gateway sends challenge before accepting connect
            if let nonce = payload?["nonce"] as? String {
                challengeNonce = nonce
                sendConnectHandshake()
            }
            
        case "chat":
            handleChatEvent(payload)
            
        case "session.status":
            if let payload {
                updateSessionDetails(from: payload)
            }
            
        case "agent.started", "agent.completed":
            if let data = payload,
               let agentData = try? JSONSerialization.data(withJSONObject: data),
               let agent = try? JSONDecoder().decode(AgentInfo.self, from: agentData) {
                if event == "agent.started" {
                    activeAgents.append(agent)
                } else {
                    activeAgents.removeAll { $0.id == agent.id }
                }
                activeSubAgentCount = activeAgents.count
            }
            
        default:
            break
        }
    }
    
    private func handleChatEvent(_ payload: [String: Any]?) {
        guard let payload else { return }
        
        let state = payload["state"] as? String ?? ""
        
        switch state {
        case "delta":
            // Streaming delta — show in thinking bubble, NOT as a message
            let message = payload["message"]
            let text = extractText(from: message)
            if !text.isEmpty {
                isThinking = true
                thinkingText = text
                // Also accumulate for quick commands
                if quickCommandCallback != nil {
                    quickCommandStreamText = text  // delta sends full accumulated text, not incremental
                }
            }
            
        case "final":
            // Stream complete — clear thinking
            isThinking = false
            thinkingText = ""
            
            if let cb = quickCommandCallback {
                quickCommandCallback = nil
                quickCommandWatchdog?.cancel()
                quickCommandWatchdog = nil
                
                // Use accumulated stream text if available, otherwise reload history
                if !quickCommandStreamText.isEmpty {
                    let response = quickCommandStreamText
                    quickCommandStreamText = ""
                    cb(response)
                } else {
                    // Fallback: reload history and grab last message
                    loadChatHistory()
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        if let lastAssistant = self.messages.last(where: { !$0.isFromUser }) {
                            cb(lastAssistant.text)
                        } else {
                            cb(nil)
                        }
                    }
                }
                currentStreamText = ""
            } else {
                currentStreamText = ""
                loadChatHistory()
                fetchSessionStatus()
            }
            
        case "error":
            let errMsg = payload["errorMessage"] as? String ?? "Chat error"
            isThinking = false
            thinkingText = ""
            currentStreamText = ""
            addSystemMessage("⚠️ \(errMsg)")
            
        case "aborted":
            isThinking = false
            thinkingText = ""
            currentStreamText = ""
            addSystemMessage("[Response aborted]")
            
        default:
            break
        }
    }
    
    private func startUptimeTimer() {
        uptimeTask?.cancel()
        uptimeTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled, let connectedAt {
                    sessionUptime = Date().timeIntervalSince(connectedAt)
                }
            }
        }
    }
    
    private func startPing() {
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled {
                    webSocket?.sendPing { _ in }
                }
            }
        }
    }
    
    /// Handle a transient disconnect — give a 3s grace period before showing UI disconnect
    private func handleTransientDisconnect() {
        // Cancel existing grace task
        disconnectGraceTask?.cancel()
        
        // Clean up socket silently
        pingTask?.cancel()
        uptimeTask?.cancel()
        activeSessionsTask?.cancel()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        challengeNonce = nil
        pendingRequests.removeAll()
        
        // Start grace period — only show disconnect UI if reconnect fails within 3s
        disconnectGraceTask = Task {
            // Try reconnecting immediately (silently)
            suppressDisconnectHaptic = true
            self.silentReconnect()
            
            // Wait 3 seconds
            try? await Task.sleep(for: .seconds(3))
            
            // If still not connected after grace period, show disconnect UI
            if !Task.isCancelled && !self.isConnected {
                self.isConnected = false
                self.connectedAt = nil
                self.sessionUptime = 0
                let warning = UINotificationFeedbackGenerator()
                warning.notificationOccurred(.warning)
                self.syncToSharedState()
                self.endLiveActivity()
            }
            self.suppressDisconnectHaptic = false
        }
    }
    
    /// Reconnect without triggering disconnect UI/haptics
    private func silentReconnect() {
        guard let url = gatewayURL else { return }
        
        connectionError = nil
        challengeNonce = nil
        
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        
        var request = URLRequest(url: url)
        request.setValue(url.absoluteString, forHTTPHeaderField: "Origin")
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()
        
        receiveMessage()
    }
    
    private func scheduleReconnect() {
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled {
                connect()
            }
        }
    }
    
    private func fetchSessionStatus() {
        sendRequest(method: "sessions.list", params: [
            "activeMinutes": 30,
            "limit": 10
        ]) { [weak self] response in
            Task { @MainActor in
                guard let self,
                      let data = response,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = json["payload"] as? [String: Any],
                      let sessions = payload["sessions"] as? [[String: Any]],
                      !sessions.isEmpty else { return }
                let sessionInfo = sessions.first(where: { ($0["key"] as? String) == self.sessionKey }) ?? sessions.first
                if let sessionInfo {
                    self.updateSessionDetails(from: sessionInfo)
                }
            }
        }
    }
    
    private func updateSessionDetails(from dictionary: [String: Any]) {
        if let task = dictionary["currentTask"] as? String {
            currentTask = task
        }
        if let model = (dictionary["model"] as? String) ?? (dictionary["activeModel"] as? String) {
            modelName = model
        }
        if let uptime = parseUptime(from: dictionary) {
            sessionUptime = uptime
        }
        if let agents = dictionary["activeAgents"] as? [[String: Any]] {
            activeAgents = decodeAgents(from: agents)
            activeSubAgentCount = activeAgents.count
        } else if let count = dictionary["activeAgentCount"] as? Int {
            activeSubAgentCount = count
        } else if let count = dictionary["activeAgentsCount"] as? Int {
            activeSubAgentCount = count
        }
        
        // Update Live Activity and shared state for widgets
        updateLiveActivity()
        syncToSharedState()
    }
    
    private func parseUptime(from dictionary: [String: Any]) -> TimeInterval? {
        if let uptime = dictionary["uptimeSeconds"] as? Double {
            return uptime
        }
        if let uptime = dictionary["uptimeSeconds"] as? Int {
            return Double(uptime)
        }
        if let uptime = dictionary["uptime"] as? Double {
            return uptime
        }
        if let uptime = dictionary["uptime"] as? Int {
            return Double(uptime)
        }
        if let startedAtMs = dictionary["startedAt"] as? Double {
            let seconds = startedAtMs > 1_000_000_000_000 ? startedAtMs / 1000 : startedAtMs
            let uptime = Date().timeIntervalSince1970 - seconds
            return max(uptime, 0)
        }
        if let startedAtString = dictionary["startedAt"] as? String,
           let date = iso8601Formatter.date(from: startedAtString) {
            return Date().timeIntervalSince(date)
        }
        return nil
    }
    
    private func decodeAgents(from array: [[String: Any]]) -> [AgentInfo] {
        array.compactMap { item in
            guard let id = (item["id"] as? String) ?? (item["agentId"] as? String) else { return nil }
            let name = (item["name"] as? String) ?? (item["label"] as? String) ?? "Agent"
            let status = (item["status"] as? String) ?? (item["state"] as? String) ?? "active"
            let model = (item["model"] as? String) ?? (item["modelName"] as? String)
            return AgentInfo(id: id, name: name, status: status, model: model)
        }
    }
    
    // MARK: - Active Sessions
    
    func fetchActiveSessions() {
        guard isConnected else {
            print("[AgentTree] Not connected, skipping fetch")
            return
        }
        print("[AgentTree] Sending sessions.list request...")
        sendRequest(method: "sessions.list", params: [
            "limit": 50,
            "messageLimit": 1
        ]) { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                guard let data = response else {
                    print("[AgentTree] No response data (nil)")
                    self.activeSessions = []
                    return
                }
                
                let responseString = String(data: data, encoding: .utf8) ?? "nil"
                print("[AgentTree] Raw response (\(data.count) bytes): \(String(responseString.prefix(800)))")
                
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[AgentTree] Failed to parse JSON")
                    self.activeSessions = []
                    return
                }
                
                // Check for error response
                if let error = json["error"] as? String {
                    print("[AgentTree] Gateway error: \(error)")
                    self.activeSessions = []
                    return
                }
                
                print("[AgentTree] JSON keys: \(Array(json.keys))")
                
                // Try multiple response shapes: payload.sessions, result.sessions, or top-level sessions
                let sessions: [[String: Any]]? =
                    (json["payload"] as? [String: Any])?["sessions"] as? [[String: Any]]
                    ?? (json["result"] as? [String: Any])?["sessions"] as? [[String: Any]]
                    ?? json["sessions"] as? [[String: Any]]
                
                guard let sessions else {
                    print("[AgentTree] No 'sessions' array found in response keys: \(Array(json.keys))")
                    self.activeSessions = []
                    return
                }
                
                print("[AgentTree] Found \(sessions.count) sessions")
                var mapped: [ActiveSession] = []
                for (i, dict) in sessions.enumerated() {
                    if let session = self.decodeActiveSession(from: dict) {
                        mapped.append(session)
                    } else {
                        let key = dict["key"] as? String ?? "unknown"
                        print("[AgentTree] Failed to decode session \(i): key=\(key), keys=\(Array(dict.keys))")
                    }
                }
                mapped.sort(by: { $0.updatedAt > $1.updatedAt })
                print("[AgentTree] Parsed \(mapped.count)/\(sessions.count) sessions")
                self.activeSessions = mapped
            }
        }
    }
    
    private func decodeActiveSession(from dictionary: [String: Any]) -> ActiveSession? {
        guard let key = dictionary["key"] as? String else { return nil }
        let displayName = (dictionary["displayName"] as? String) ?? ""
        let rawLabel = (dictionary["label"] as? String) ?? ""
        let label = !rawLabel.isEmpty ? rawLabel : (!displayName.isEmpty ? displayName : key)
        let model = (dictionary["model"] as? String) ?? (dictionary["activeModel"] as? String) ?? "Unknown"
        let lastMessage = extractLastMessage(from: dictionary)
        let updatedAt = parseUpdatedAt(from: dictionary) ?? Date()
        let totalTokens = (dictionary["totalTokens"] as? Int) ?? 0
        
        // Classify by key pattern
        let kind: SessionKind
        if key.contains(":subagent:") {
            kind = .subagent
        } else if key.contains(":cron:") {
            kind = .cron
        } else if key.contains(":group:") || key.contains(":channel:") {
            kind = .group
        } else if key.hasSuffix(":main") {
            kind = .main
        } else {
            kind = .other
        }
        
        // Active = updated in last 5 minutes
        let isActive = updatedAt.timeIntervalSinceNow > -300
        
        return ActiveSession(
            key: key,
            model: model,
            label: label,
            updatedAt: updatedAt,
            lastMessage: lastMessage,
            isActive: isActive,
            kind: kind,
            totalTokens: totalTokens
        )
    }
    
    private func extractLastMessage(from dictionary: [String: Any]) -> String {
        if let task = dictionary["currentTask"] as? String, !task.isEmpty {
            return task
        }
        if let messages = dictionary["messages"] as? [[String: Any]],
           let latest = messages.first,
           let content = latest["content"] {
            let text = extractText(from: content)
            if !text.isEmpty {
                return text
            }
        }
        if let summary = dictionary["summary"] as? String, !summary.isEmpty {
            return summary
        }
        return "Idle"
    }
    
    private func parseUpdatedAt(from dictionary: [String: Any]) -> Date? {
        if let updated = dictionary["updatedAt"] as? Double {
            let seconds = updated > 1_000_000_000_000 ? updated / 1000 : updated
            return Date(timeIntervalSince1970: seconds)
        }
        if let updated = dictionary["updatedAt"] as? Int {
            let seconds = updated > 1_000_000_000 ? Double(updated) / 1000 : Double(updated)
            return Date(timeIntervalSince1970: seconds)
        }
        if let updatedString = dictionary["updatedAt"] as? String {
            if let numeric = Double(updatedString) {
                let seconds = numeric > 1_000_000_000_000 ? numeric / 1000 : numeric
                return Date(timeIntervalSince1970: seconds)
            }
            if let date = iso8601Formatter.date(from: updatedString) {
                return date
            }
        }
        if let lastMessage = dictionary["lastMessageAt"] as? Double {
            let seconds = lastMessage > 1_000_000_000_000 ? lastMessage / 1000 : lastMessage
            return Date(timeIntervalSince1970: seconds)
        }
        if let lastMessage = dictionary["lastMessageAt"] as? Int {
            let seconds = lastMessage > 1_000_000_000 ? Double(lastMessage) / 1000 : Double(lastMessage)
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
    
    private func startActiveSessionsPolling() {
        activeSessionsTask?.cancel()
        activeSessionsTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await MainActor.run {
                    self.fetchActiveSessions()
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

// MARK: - TLS Delegate for Tailscale Serve certificates

/// Tailscale Serve uses TLS certificates from its own CA which iOS doesn't trust by default.
/// This delegate accepts certificates for *.ts.net domains specifically.
final class TailscaleTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              challenge.protectionSpace.host.hasSuffix(".ts.net") else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Trust the Tailscale Serve certificate for *.ts.net hosts
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
