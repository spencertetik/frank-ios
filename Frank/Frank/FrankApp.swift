import SwiftUI
import EventKit

@main
struct FrankApp: App {
    @State private var statusModel = FrankStatusModel()
    @State private var gateway = GatewayClient()
    @State private var calendarManager = CalendarManager()
    @State private var notificationManager = NotificationManager()
    @State private var quickCommandCache = QuickCommandCache()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(statusModel)
                .environment(gateway)
                .environment(calendarManager)
                .environment(notificationManager)
                .environment(quickCommandCache)
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
                    // Request notification permissions on app launch
                    await notificationManager.requestPermissions()
                    
                    // Start connection monitoring
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