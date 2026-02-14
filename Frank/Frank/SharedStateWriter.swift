import Foundation
import Observation
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
        
        static let claudeSessionPercent = "frank.claudeSessionPercent"
        static let claudeSessionResetAt = "frank.claudeSessionResetAt"
        static let claudeWeeklyPercent = "frank.claudeWeeklyPercent"
        static let claudeWeeklyResetAt = "frank.claudeWeeklyResetAt"
        static let claudeSonnetPercent = "frank.claudeSonnetPercent"
        static let claudeExtraUsagePercent = "frank.claudeExtraUsagePercent"
        static let claudeExtraUsageDollars = "frank.claudeExtraUsageDollars"
        static let claudeExtraUsageLimit = "frank.claudeExtraUsageLimit"
        static let codexSessionPercent = "frank.codexSessionPercent"
        static let codexWeeklyPercent = "frank.codexWeeklyPercent"
        static let apiSpendToday = "frank.apiSpendToday"
        static let apiSpend7Day = "frank.apiSpend7Day"
        static let apiSpend30Day = "frank.apiSpend30Day"
    }
    
    struct UsageSnapshot: Equatable {
        var claudeSessionPercent: Double = 0
        var claudeSessionResetAt: Date? = nil
        var claudeWeeklyPercent: Double = 0
        var claudeWeeklyResetAt: Date? = nil
        var claudeSonnetPercent: Double = 0
        var claudeExtraUsagePercent: Double = 0
        var claudeExtraUsageDollars: Double = 0
        var claudeExtraUsageLimit: Double = 0
        var codexSessionPercent: Double = 0
        var codexWeeklyPercent: Double = 0
        var apiSpendToday: Double = 0
        var apiSpend7Day: Double = 0
        var apiSpend30Day: Double = 0
    }
    
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }()
    
    private static var usageObserver: UsageObserver?
    @MainActor private(set) static var cachedUsageSnapshot = UsageSnapshot()
    
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
    
    @MainActor
    static func bindUsageServices(
        claudeUsageService: ClaudeUsageService,
        codexUsageService: CodexUsageService
    ) {
        usageObserver = UsageObserver(
            claudeUsageService: claudeUsageService,
            codexUsageService: codexUsageService
        )
    }
    
    @MainActor
    static func currentUsageSnapshot() -> UsageSnapshot {
        cachedUsageSnapshot
    }
    
    @MainActor
    fileprivate static func writeUsage(
        claudeUsageService: ClaudeUsageService,
        codexUsageService: CodexUsageService
    ) {
        let spend = spendTotals(from: codexUsageService)
        let snapshot = UsageSnapshot(
            claudeSessionPercent: sanitizePercent(claudeUsageService.fiveHour?.utilization),
            claudeSessionResetAt: claudeUsageService.fiveHour?.resetsAt,
            claudeWeeklyPercent: sanitizePercent(claudeUsageService.sevenDay?.utilization),
            claudeWeeklyResetAt: claudeUsageService.sevenDay?.resetsAt,
            claudeSonnetPercent: sanitizePercent(claudeUsageService.sevenDaySonnet?.utilization),
            claudeExtraUsagePercent: sanitizePercent(claudeUsageService.extraUsage?.utilization),
            claudeExtraUsageDollars: dollars(from: claudeUsageService.extraUsage?.usedCredits),
            claudeExtraUsageLimit: dollars(from: claudeUsageService.extraUsage?.monthlyLimit),
            codexSessionPercent: sanitizePercent(codexUsageService.sessionWindow?.usedPercent),
            codexWeeklyPercent: sanitizePercent(codexUsageService.weeklyWindow?.usedPercent),
            apiSpendToday: spend.today,
            apiSpend7Day: spend.seven,
            apiSpend30Day: spend.thirty
        )
        persistUsage(snapshot)
    }
    
    @MainActor
    private static func persistUsage(_ snapshot: UsageSnapshot) {
        guard cachedUsageSnapshot != snapshot else { return }
        cachedUsageSnapshot = snapshot
        guard let defaults else { return }
        defaults.set(snapshot.claudeSessionPercent, forKey: Keys.claudeSessionPercent)
        if let reset = snapshot.claudeSessionResetAt {
            defaults.set(isoFormatter.string(from: reset), forKey: Keys.claudeSessionResetAt)
        } else {
            defaults.removeObject(forKey: Keys.claudeSessionResetAt)
        }
        defaults.set(snapshot.claudeWeeklyPercent, forKey: Keys.claudeWeeklyPercent)
        if let reset = snapshot.claudeWeeklyResetAt {
            defaults.set(isoFormatter.string(from: reset), forKey: Keys.claudeWeeklyResetAt)
        } else {
            defaults.removeObject(forKey: Keys.claudeWeeklyResetAt)
        }
        defaults.set(snapshot.claudeSonnetPercent, forKey: Keys.claudeSonnetPercent)
        defaults.set(snapshot.claudeExtraUsagePercent, forKey: Keys.claudeExtraUsagePercent)
        defaults.set(snapshot.claudeExtraUsageDollars, forKey: Keys.claudeExtraUsageDollars)
        defaults.set(snapshot.claudeExtraUsageLimit, forKey: Keys.claudeExtraUsageLimit)
        defaults.set(snapshot.codexSessionPercent, forKey: Keys.codexSessionPercent)
        defaults.set(snapshot.codexWeeklyPercent, forKey: Keys.codexWeeklyPercent)
        defaults.set(snapshot.apiSpendToday, forKey: Keys.apiSpendToday)
        defaults.set(snapshot.apiSpend7Day, forKey: Keys.apiSpend7Day)
        defaults.set(snapshot.apiSpend30Day, forKey: Keys.apiSpend30Day)
        reloadWidgets()
    }
    
    private static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Usage Observation

@MainActor
private final class UsageObserver {
    private let claudeUsageService: ClaudeUsageService
    private let codexUsageService: CodexUsageService
    
    init(
        claudeUsageService: ClaudeUsageService,
        codexUsageService: CodexUsageService
    ) {
        self.claudeUsageService = claudeUsageService
        self.codexUsageService = codexUsageService
        observe()
    }
    
    private func observe() {
        withObservationTracking {
            SharedStateWriter.writeUsage(
                claudeUsageService: claudeUsageService,
                codexUsageService: codexUsageService
            )
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.observe()
            }
        }
    }
}

// MARK: - Helpers

private func sanitizePercent(_ value: Double?) -> Double {
    let clamped = max(0, value ?? 0)
    return min(clamped, 150)
}

private func dollars(from centsValue: Double?) -> Double {
    guard let centsValue else { return 0 }
    return centsValue / 100
}

private func spendTotals(from service: CodexUsageService) -> (today: Double, seven: Double, thirty: Double) {
    let calendar = Calendar(identifier: .gregorian)
    let todayStart = calendar.startOfDay(for: Date())
    var todayTotal = 0.0
    var sevenTotal = 0.0
    var thirtyTotal = 0.0
    for cost in service.dailyCosts {
        let day = calendar.startOfDay(for: cost.date)
        guard let days = calendar.dateComponents([.day], from: day, to: todayStart).day else { continue }
        if days == 0 { todayTotal += cost.amount }
        if days >= 0 && days <= 6 { sevenTotal += cost.amount }
        if days >= 0 && days <= 29 { thirtyTotal += cost.amount }
    }
    return (todayTotal, sevenTotal, thirtyTotal)
}
