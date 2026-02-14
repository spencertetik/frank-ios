import Foundation
import UserNotifications
import Observation
import EventKit

@Observable
@MainActor
final class NotificationManager {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var hasRequestedPermissions = false
    
    private let center = UNUserNotificationCenter.current()
    
    init() {
        setupNotificationCategories()
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    func requestPermissions() async {
        guard !hasRequestedPermissions else { return }
        hasRequestedPermissions = true
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            print("Notification permission request failed: \(error)")
            authorizationStatus = .denied
        }
    }
    
    func checkAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }
    
    // MARK: - Calendar Reminders
    
    func scheduleCalendarReminder(for event: EKEvent, minutesBefore: Int = 15) {
        guard authorizationStatus == .authorized else { return }
        
        let triggerDate = event.startDate.addingTimeInterval(TimeInterval(-minutesBefore * 60))
        guard triggerDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "📅 Upcoming Event"
        content.body = "\(event.title ?? "Untitled Event") starts in \(minutesBefore) minutes"
        content.sound = .default
        content.categoryIdentifier = "CALENDAR_REMINDER"
        
        let calendar = Calendar.current
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let identifier = "calendar_reminder_\(event.eventIdentifier ?? UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("Failed to schedule calendar reminder: \(error)")
            }
        }
    }
    
    // MARK: - Connection Notifications
    
    func notifyConnectionLost() {
        guard authorizationStatus == .authorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "🔴 Frank Disconnected"
        content.body = "Connection to Frank has been lost"
        content.sound = .default
        content.categoryIdentifier = "CONNECTION_STATUS"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "connection_lost", content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("Failed to send connection lost notification: \(error)")
            }
        }
    }
    
    func notifyConnectionRestored() {
        // Remove connection lost notification
        center.removePendingNotificationRequests(withIdentifiers: ["connection_lost"])
        center.removeDeliveredNotifications(withIdentifiers: ["connection_lost"])
        
        guard authorizationStatus == .authorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "🟢 Frank Connected"
        content.body = "Connection to Frank has been restored"
        content.sound = .default
        content.categoryIdentifier = "CONNECTION_STATUS"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "connection_restored", content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("Failed to send connection restored notification: \(error)")
            }
        }
    }
    
    // MARK: - Message Notifications
    
    func notifyUrgentMessage(_ text: String) {
        guard authorizationStatus == .authorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "🚨 Urgent Message from Frank"
        content.body = String(text.prefix(100))
        content.sound = .default
        content.categoryIdentifier = "URGENT_MESSAGE"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "urgent_message_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("Failed to send urgent message notification: \(error)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationCategories() {
        let calendarCategory = UNNotificationCategory(
            identifier: "CALENDAR_REMINDER",
            actions: [
                UNNotificationAction(identifier: "SNOOZE", title: "Snooze 5min", options: []),
                UNNotificationAction(identifier: "DISMISS", title: "Dismiss", options: [.destructive])
            ],
            intentIdentifiers: []
        )
        
        let connectionCategory = UNNotificationCategory(
            identifier: "CONNECTION_STATUS",
            actions: [
                UNNotificationAction(identifier: "OPEN_APP", title: "Open App", options: [.foreground])
            ],
            intentIdentifiers: []
        )
        
        let urgentMessageCategory = UNNotificationCategory(
            identifier: "URGENT_MESSAGE",
            actions: [
                UNNotificationAction(identifier: "REPLY", title: "Reply", options: [.foreground]),
                UNNotificationAction(identifier: "MARK_READ", title: "Mark Read", options: [])
            ],
            intentIdentifiers: []
        )
        
        center.setNotificationCategories([calendarCategory, connectionCategory, urgentMessageCategory])
    }
    
    // MARK: - Utility Methods
    
    func cancelCalendarReminder(for eventIdentifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["calendar_reminder_\(eventIdentifier)"])
    }
    
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

// MARK: - Connection Monitoring Extension

extension NotificationManager {
    /// Monitor connection status with a grace period before notifying
    func startConnectionMonitoring(with gateway: GatewayClient) {
        var disconnectTask: Task<Void, Never>?
        
        // Monitor connection changes using polling (withObservationTracking)
        Task {
            var wasDisconnected = false
            while !Task.isCancelled {
                let isConnected = gateway.isConnected
                if isConnected {
                    // Connected - cancel any pending disconnect notification
                    disconnectTask?.cancel()
                    disconnectTask = nil
                    
                    // Only notify about reconnection if we previously lost connection
                    if gateway.connectionError != nil {
                        notifyConnectionRestored()
                    }
                    wasDisconnected = false
                } else {
                    if !wasDisconnected {
                        wasDisconnected = true
                        // Disconnected - start grace period timer
                        disconnectTask = Task {
                            try? await Task.sleep(for: .seconds(30))
                            if !Task.isCancelled && !gateway.isConnected {
                                notifyConnectionLost()
                            }
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

// MARK: - Auto Calendar Reminders Extension

extension NotificationManager {
    /// Auto-schedule reminders for upcoming events
    func autoScheduleReminders(for events: [CalendarManager.CalendarEvent]) {
        // Only schedule reminders for events in the next 24 hours
        let cutoffDate = Date().addingTimeInterval(24 * 60 * 60)
        
        for event in events {
            guard event.startDate <= cutoffDate else { continue }
            
            // Schedule local notification directly
            let content = UNMutableNotificationContent()
            content.title = "📅 Coming Up"
            content.body = "\(event.title) in 15 minutes"
            content.sound = .default
            content.categoryIdentifier = "CALENDAR_REMINDER"
            
            let triggerDate = event.startDate.addingTimeInterval(-15 * 60)
            guard triggerDate > Date() else { continue }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let request = UNNotificationRequest(identifier: "cal-\(event.id)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }
}