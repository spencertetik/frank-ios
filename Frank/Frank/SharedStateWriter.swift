import Foundation
import WidgetKit

/// Writes widget shared state data into the App Group container used by Frank widgets.
/// App Group: group.com.openclaw.Frank
enum SharedStateWriter {
    private static let suiteName = "group.com.openclaw.Frank"
    
    private enum Keys {
        static let isConnected = "frank.isConnected"
        static let currentTask = "frank.currentTask"
        static let modelName = "frank.modelName"
        static let subAgentCount = "frank.subAgentCount"
        static let sessionUptime = "frank.sessionUptime"
        static let lastMessage = "frank.lastMessage"
        static let messagesToday = "frank.messagesToday"
        static let upcomingEvents = "frank.upcomingEvents"
        static let lastUpdated = "frank.lastUpdated"
    }
    
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
    
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
        reloadWidgets()
    }
    
    static func updateEvents(_ events: [[String: String]]) {
        guard let defaults else { return }
        if let data = try? JSONSerialization.data(withJSONObject: events) {
            defaults.set(data, forKey: Keys.upcomingEvents)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastUpdated)
            reloadWidgets()
        }
    }
    
    private static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
