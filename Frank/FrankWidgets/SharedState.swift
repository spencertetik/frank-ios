import Foundation

/// Shared state between main app and widget extension via App Groups UserDefaults
/// App Group: group.com.openclaw.Frank
/// Widget-side copy (read-only, no WidgetKit reload calls)
struct SharedState {
    static let suiteName = "group.com.openclaw.Frank"
    
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
    
    // MARK: - Keys
    private enum Keys {
        static let isConnected = "frank.isConnected"
        static let currentTask = "frank.currentTask"
        static let modelName = "frank.modelName"
        static let subAgentCount = "frank.subAgentCount"
        static let sessionUptime = "frank.sessionUptime"
        static let lastMessage = "frank.lastMessage"
        static let messagesToday = "frank.messagesToday"
        static let lastUpdated = "frank.lastUpdated"
        static let upcomingEvents = "frank.upcomingEvents"
    }
    
    // MARK: - Write (from main app)
    
    static func update(
        isConnected: Bool,
        currentTask: String,
        modelName: String,
        subAgentCount: Int,
        sessionUptime: TimeInterval,
        lastMessage: String,
        messagesToday: Int
    ) {
        guard let defaults else { return }
        defaults.set(isConnected, forKey: Keys.isConnected)
        defaults.set(currentTask, forKey: Keys.currentTask)
        defaults.set(modelName, forKey: Keys.modelName)
        defaults.set(subAgentCount, forKey: Keys.subAgentCount)
        defaults.set(sessionUptime, forKey: Keys.sessionUptime)
        defaults.set(lastMessage, forKey: Keys.lastMessage)
        defaults.set(messagesToday, forKey: Keys.messagesToday)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastUpdated)
        
        // Widget-side: no reload call needed
    }
    
    static func updateEvents(_ events: [[String: String]]) {
        guard let defaults else { return }
        if let data = try? JSONSerialization.data(withJSONObject: events) {
            defaults.set(data, forKey: Keys.upcomingEvents)
        }
    }
    
    // MARK: - Read (from widget extension)
    
    static var isConnected: Bool {
        defaults?.bool(forKey: Keys.isConnected) ?? false
    }
    
    static var currentTask: String {
        defaults?.string(forKey: Keys.currentTask) ?? "Waiting for connection"
    }
    
    static var modelName: String {
        defaults?.string(forKey: Keys.modelName) ?? "—"
    }
    
    static var subAgentCount: Int {
        defaults?.integer(forKey: Keys.subAgentCount) ?? 0
    }
    
    static var sessionUptime: TimeInterval {
        defaults?.double(forKey: Keys.sessionUptime) ?? 0
    }
    
    static var lastMessage: String {
        defaults?.string(forKey: Keys.lastMessage) ?? "No messages yet"
    }
    
    static var messagesToday: Int {
        defaults?.integer(forKey: Keys.messagesToday) ?? 0
    }
    
    static var lastUpdated: Date? {
        let ts = defaults?.double(forKey: Keys.lastUpdated) ?? 0
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }
    
    static var upcomingEvents: [[String: String]] {
        guard let defaults,
              let data = defaults.data(forKey: Keys.upcomingEvents),
              let events = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return []
        }
        return events
    }
}
