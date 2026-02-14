import ActivityKit
import Foundation

/// Shared ActivityAttributes for Frank Live Activities
/// This file is accessible to both the main app and the FrankLiveActivity widget extension
struct FrankActivityAttributes: ActivityAttributes {
    /// Static attributes that don't change during the activity
    public struct ContentState: Codable, Hashable {
        /// The current status/mood of Frank
        var frankStatus: String
        /// Current task Frank is working on
        var currentTask: String
        /// The AI model Frank is currently using
        var modelName: String
        /// Last message in the conversation
        var lastMessage: String
        /// Whether Frank is connected to the gateway
        var isConnected: Bool
        /// Number of active sub-agents
        var subAgentCount: Int
        /// Session uptime in seconds
        var uptime: TimeInterval
        /// Timestamp of the last update
        var lastUpdated: Date
        /// Claude session utilization percent (0-100)
        var claudeSessionPercent: Double
        /// When the Claude session resets
        var claudeSessionResetAt: Date?
        /// Claude weekly utilization percent
        var claudeWeeklyPercent: Double
        /// Codex session utilization percent
        var codexSessionPercent: Double
    }
    
    /// Static data that doesn't change during the activity
    /// Currently empty as Frank's data is mostly dynamic
    public let staticData: EmptyAttributes = EmptyAttributes()
    
    public struct EmptyAttributes: Codable, Hashable {
        // Empty struct for static attributes
    }
}

/// Convenience extensions for formatting data
extension FrankActivityAttributes.ContentState {
    /// Formatted uptime string for display
    var uptimeString: String {
        guard uptime > 1 else { return "—" }
        
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = uptime >= 3600 ? [.hour, .minute] : [.minute, .second]
        return formatter.string(from: uptime) ?? "—"
    }
    
    /// Truncated task string for compact views
    var compactTask: String {
        if currentTask.count > 32 {
            return String(currentTask.prefix(29)) + "…"
        }
        return currentTask
    }
    
    /// Formatted Claude session usage string
    var claudeSessionDisplay: String {
        "\(Int(claudeSessionPercent.rounded()))%"
    }
    
    /// Truncated model name for UI
    var displayModel: String {
        let parts = modelName.split(separator: "/")
        if let last = parts.last {
            return String(last)
        }
        return modelName
    }
}
