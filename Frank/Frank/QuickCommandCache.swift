import SwiftUI
import Foundation

@Observable @MainActor
final class QuickCommandCache {
    
    enum CommandType: String, Codable, CaseIterable, Identifiable {
        case morningReport = "morning_report"
        case weather = "weather"
        case email = "check_email"
        case projectStatus = "project_status"
        case whatsNext = "whats_next"
        case summarizeChat = "summarize_chat"
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .morningReport: return "Morning Report"
            case .weather: return "Weather"
            case .email: return "Check Email"
            case .projectStatus: return "Project Status"
            case .whatsNext: return "What's Next?"
            case .summarizeChat: return "Summarize Chat"
            }
        }
        
        var icon: String {
            switch self {
            case .morningReport: return "sun.max"
            case .weather: return "cloud.sun"
            case .email: return "envelope"
            case .projectStatus: return "folder"
            case .whatsNext: return "target"
            case .summarizeChat: return "doc.text"
            }
        }
        
        var emoji: String {
            switch self {
            case .morningReport: return "☀️"
            case .weather: return "🌤️"
            case .email: return "✉️"
            case .projectStatus: return "📊"
            case .whatsNext: return "🎯"
            case .summarizeChat: return "📝"
            }
        }
        
        /// The prompt sent to the gateway — this goes to an isolated session, NOT main chat
        var prompt: String {
            switch self {
            case .morningReport: return "Give me my morning report - calendar, weather, and any urgent items. Keep it concise."
            case .weather: return "What's the weather like today in Perry, OK? Any alerts or recommendations? Keep it concise."
            case .email: return "Check my email for anything urgent or important. Keep it concise."
            case .projectStatus: return "Give me a brief status update on current projects."
            case .whatsNext: return "What should I focus on next? What are my priorities? Keep it brief."
            case .summarizeChat: return "Summarize our recent conversation and any action items. Keep it brief."
            }
        }
    }
    
    struct CachedResult: Codable, Identifiable {
        var id: String { commandType.rawValue }
        let commandType: CommandType
        var content: String
        var timestamp: Date
        var isLoading: Bool
        
        var isEmpty: Bool { content.isEmpty && !isLoading }
    }
    
    // MARK: - State
    
    var results: [CommandType: CachedResult] = [:]
    
    private let cacheKey = "QuickCommandCache.v2"
    
    init() { load() }
    
    // MARK: - Public
    
    func result(for type: CommandType) -> CachedResult? { results[type] }
    
    func lastUpdated(_ type: CommandType) -> String {
        guard let r = results[type] else { return "Never" }
        return relativeTime(r.timestamp)
    }
    
    func isStale(_ type: CommandType) -> Bool {
        guard let r = results[type] else { return true }
        return r.timestamp.addingTimeInterval(4 * 3600) < Date()
    }
    
    /// Fetch via a dedicated gateway request (NOT through main chat)
    func fetch(_ type: CommandType, gateway: GatewayClient) {
        // Mark loading
        results[type] = CachedResult(
            commandType: type,
            content: results[type]?.content ?? "",
            timestamp: results[type]?.timestamp ?? Date(),
            isLoading: true
        )
        
        // Use chat.send with deliver:false and a separate "quick command" idempotency
        // so it doesn't show in main chat, then capture via response callback
        gateway.sendQuickCommand(prompt: type.prompt, commandId: type.rawValue) { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                self.results[type] = CachedResult(
                    commandType: type,
                    content: response ?? "Failed to get response. Try again.",
                    timestamp: Date(),
                    isLoading: false
                )
                self.save()
            }
        }
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: CachedResult].self, from: data) else { return }
        for (key, val) in decoded {
            if let ct = CommandType(rawValue: key) {
                var r = val
                r.isLoading = false // never persist loading state
                results[ct] = r
            }
        }
    }
    
    private func save() {
        let dict = Dictionary(uniqueKeysWithValues: results.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    private func relativeTime(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "Just now" }
        if s < 3600 { return "\(Int(s/60))m ago" }
        if s < 86400 { return "\(Int(s/3600))h ago" }
        return "\(Int(s/86400))d ago"
    }
}
