import SwiftUI
import EventKit
import UserNotifications
import UIKit

@main
struct FrankApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationAppDelegate.self) private var appDelegate
    @State private var statusModel: FrankStatusModel
    @State private var gateway: GatewayClient
    @State private var calendarManager: CalendarManager
    @State private var notificationManager: NotificationManager
    @State private var quickCommandCache: QuickCommandCache
    @State private var claudeUsageService: ClaudeUsageService
    @State private var codexUsageService: CodexUsageService
    @AppStorage(AccentColorManager.storageKey) private var accentColorHex = AccentColorManager.defaultHex
    @Environment(\.scenePhase) private var scenePhase

    private var accentColor: Color { AccentColorManager.color(from: accentColorHex) }

    init() {
        let statusModel = FrankStatusModel()
        let gateway = GatewayClient()
        let calendarManager = CalendarManager()
        let notificationManager = NotificationManager()
        let quickCommandCache = QuickCommandCache()
        let claudeUsageService = ClaudeUsageService()
        let codexUsageService = CodexUsageService()

        _statusModel = State(initialValue: statusModel)
        _gateway = State(initialValue: gateway)
        _calendarManager = State(initialValue: calendarManager)
        _notificationManager = State(initialValue: notificationManager)
        _quickCommandCache = State(initialValue: quickCommandCache)
        _claudeUsageService = State(initialValue: claudeUsageService)
        _codexUsageService = State(initialValue: codexUsageService)
        SharedStateWriter.bindUsageServices(
            claudeUsageService: claudeUsageService,
            codexUsageService: codexUsageService
        )

        appDelegate.configurePushHandling(
            onTokenUpdate: { token in
                Task { @MainActor in
                    gateway.sendPushToken(token)
                }
            },
            onPermissionChange: {
                Task { @MainActor in
                    notificationManager.checkAuthorizationStatus()
                }
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(statusModel)
                .environment(gateway)
                .environment(calendarManager)
                .environment(notificationManager)
                .environment(quickCommandCache)
                .environment(claudeUsageService)
                .environment(codexUsageService)
                .tint(accentColor)
                .onAppear {
                    setupApp()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
                .onChange(of: gateway.isConnected) { _, connected in
                    handleConnectionChange(connected)
                }
                .task {
                    notificationManager.startConnectionMonitoring(with: gateway)
                }
        }
    }
    
    // MARK: - Setup
    
    private func setupApp() {
        setupGateway()
        setupCalendar()
        setupNotifications()
    }
    
    private func setupGateway() {
        // One-time migration: update old Tailscale IP to hostname for Serve mode
        let migrationKey = "tailscaleMigratedToTailnet_v3"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            // Gateway binds to tailnet IP directly — use ws:// to 100.118.254.15
            UserDefaults.standard.set("100.118.254.15", forKey: "gatewayHost")
            UserDefaults.standard.set("spencers-mac-mini.tail6878f.ts.net", forKey: "gatewayHostTailscale")
            UserDefaults.standard.set(false, forKey: "useTailscale")
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        
        let useTailscale = UserDefaults.standard.bool(forKey: "useTailscale")
        let localHost = UserDefaults.standard.string(forKey: "gatewayHost") ?? "192.168.1.197"
        let tailscaleHost = UserDefaults.standard.string(forKey: "gatewayHostTailscale") ?? "spencers-mac-mini.tail6878f.ts.net"
        let host = useTailscale ? tailscaleHost : localHost
        let token = UserDefaults.standard.string(forKey: "gatewayToken") ?? "ed7074d189b4e177ed1979f63b891a27d6f34fc8e67f7063"
        let port = UserDefaults.standard.integer(forKey: "gatewayPort")
        let autoConnect = UserDefaults.standard.object(forKey: "autoConnect") == nil ? true : UserDefaults.standard.bool(forKey: "autoConnect")
        
        if !host.isEmpty && !token.isEmpty && autoConnect {
            gateway.configure(host: host, port: port > 0 ? port : 18789, token: token, useTailscaleServe: useTailscale)
            gateway.connect()
            
            // Retry once after 2s if first connect fails (common after fresh install)
            Task {
                try? await Task.sleep(for: .seconds(2))
                if !gateway.isConnected {
                    gateway.reconnectIfNeeded()
                }
            }
        }
    }
    
    private func setupCalendar() {
        calendarManager.checkAccess()
    }
    
    private func setupNotifications() {
        // Additional notification setup if needed
        notificationManager.checkAuthorizationStatus()
    }
    
    // MARK: - Event Handlers
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App became active
            gateway.reconnectIfNeeded()
            calendarManager.fetchEvents()
            
        case .inactive:
            // App became inactive (e.g., during transitions)
            break
            
        case .background:
            // App entered background
            break
            
        @unknown default:
            break
        }
    }
    
    private func handleConnectionChange(_ connected: Bool) {
        if connected {
            // Connection established
            if calendarManager.authorizationStatus == .fullAccess {
                calendarManager.fetchEvents()
                
                // Small delay to let events load, then sync to gateway
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    await calendarManager.syncToGateway(gateway)
                    
                    // Auto-schedule calendar reminders for upcoming events
                    await scheduleCalendarReminders()
                }
            }
        } else {
            // Connection lost - notification will be handled by NotificationManager
        }
    }
    
    // MARK: - Calendar Reminders
    
    private func scheduleCalendarReminders() async {
        // Convert CalendarManager events to notification-friendly format and schedule reminders
        let events = calendarManager.upcomingEvents
        notificationManager.autoScheduleReminders(for: events)
    }
}

// CalendarEvent → EKEvent conversion removed (notifications use CalendarEvent directly)

// MARK: - Push Notifications

final class PushNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var onTokenUpdate: ((String) -> Void)?
    private var onPermissionChange: (() -> Void)?
    private let notificationCenter = UNUserNotificationCenter.current()
    private var cachedDeviceToken: String?
    
    func configurePushHandling(
        onTokenUpdate: @escaping (String) -> Void,
        onPermissionChange: @escaping () -> Void
    ) {
        self.onTokenUpdate = onTokenUpdate
        self.onPermissionChange = onPermissionChange
        if let cachedDeviceToken {
            onTokenUpdate(cachedDeviceToken)
        }
    }
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        notificationCenter.delegate = self
        requestNotificationPermissions()
        return true
    }
    
    private func requestNotificationPermissions() {
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            if let error {
                print("Push authorization request failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { [weak self] in
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                self?.onPermissionChange?()
                if !granted {
                    print("Push authorization not granted")
                }
            }
        }
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "pushDeviceToken")
        cachedDeviceToken = token
        onTokenUpdate?(token)
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
