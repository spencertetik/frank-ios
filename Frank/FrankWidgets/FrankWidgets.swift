import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Definition

struct FrankHomeWidget: Widget {
    let kind: String = "FrankHomeWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FrankWidgetProvider()) { entry in
            FrankWidgetView(entry: entry)
                .containerBackground(.thinMaterial, for: .widget)
        }
        .configurationDisplayName("Frank")
        .description("Monitor Claude/Codex usage, spend, and status")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline Provider

struct FrankWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FrankWidgetEntry {
        FrankWidgetEntry(date: Date(), snapshot: .placeholder)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (FrankWidgetEntry) -> ()) {
        let entry = FrankWidgetEntry(date: Date(), snapshot: .placeholder)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<FrankWidgetEntry>) -> ()) {
        let snapshot = FrankWidgetSnapshot.current()
        let entry = FrankWidgetEntry(date: Date(), snapshot: snapshot)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

// MARK: - Entry & Snapshot Models

struct FrankWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: FrankWidgetSnapshot
}

struct FrankWidgetSnapshot {
    struct StatusData {
        var isConnected: Bool
        var currentTask: String
        var modelName: String
        var subAgentCount: Int
        var sessionUptime: TimeInterval
        var messagesToday: Int
        var lastMessage: String
        
        var uptimeString: String {
            guard sessionUptime > 0 else { return "—" }
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = sessionUptime >= 3600 ? [.hour, .minute] : [.minute, .second]
            return formatter.string(from: sessionUptime) ?? "—"
        }
        
        var modelDisplay: String {
            let parts = modelName.split(separator: "/")
            return parts.last.map(String.init) ?? modelName
        }
    }
    
    struct UsageData {
        var claudeSessionPercent: Double
        var claudeSessionResetAt: Date?
        var claudeWeeklyPercent: Double
        var claudeWeeklyResetAt: Date?
        var claudeSonnetPercent: Double
        var claudeExtraUsagePercent: Double
        var claudeExtraUsageDollars: Double
        var claudeExtraUsageLimit: Double
        var codexSessionPercent: Double
        var codexWeeklyPercent: Double
        var apiSpendToday: Double
        var apiSpend7Day: Double
        var apiSpend30Day: Double
        
        func countdownText(for date: Date?) -> String {
            guard let date else { return "Resets soon" }
            let seconds = Int(date.timeIntervalSinceNow)
            if seconds <= 0 { return "Resets soon" }
            let minutes = seconds / 60
            if minutes < 60 {
                return "Resets in \(minutes)m"
            }
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if hours < 24 {
                return remainingMinutes == 0 ? "Resets in \(hours)h" : "Resets in \(hours)h \(remainingMinutes)m"
            }
            let days = hours / 24
            let remainingHours = hours % 24
            return remainingHours == 0 ? "Resets in \(days)d" : "Resets in \(days)d \(remainingHours)h"
        }
    }
    
    let status: StatusData
    let usage: UsageData
    let events: [CalendarWidgetEvent]
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }()
    
    static let placeholder = FrankWidgetSnapshot(
        status: StatusData(
            isConnected: true,
            currentTask: "Analyzing updates",
            modelName: "anthropic.claude-3.5",
            subAgentCount: 2,
            sessionUptime: 10_800,
            messagesToday: 18,
            lastMessage: "All systems operational"
        ),
        usage: UsageData(
            claudeSessionPercent: 42,
            claudeSessionResetAt: Date().addingTimeInterval(3600),
            claudeWeeklyPercent: 68,
            claudeWeeklyResetAt: Date().addingTimeInterval(86_400),
            claudeSonnetPercent: 25,
            claudeExtraUsagePercent: 15,
            claudeExtraUsageDollars: 42.75,
            claudeExtraUsageLimit: 100,
            codexSessionPercent: 32,
            codexWeeklyPercent: 48,
            apiSpendToday: 18.34,
            apiSpend7Day: 104.22,
            apiSpend30Day: 401.55
        ),
        events: [
            CalendarWidgetEvent(title: "Design review", startTime: Date().addingTimeInterval(3600))
        ]
    )
    
    static func current() -> FrankWidgetSnapshot {
        let events = SharedState.upcomingEvents.prefix(3).map { dict -> CalendarWidgetEvent in
            let start = isoFormatter.date(from: dict["start"] ?? "") ?? Date()
            return CalendarWidgetEvent(title: dict["title"] ?? "Event", startTime: start)
        }
        let status = StatusData(
            isConnected: SharedState.isConnected,
            currentTask: SharedState.currentTask,
            modelName: SharedState.modelName,
            subAgentCount: SharedState.subAgentCount,
            sessionUptime: SharedState.sessionUptime,
            messagesToday: SharedState.messagesToday,
            lastMessage: SharedState.lastMessage
        )
        let usage = UsageData(
            claudeSessionPercent: SharedState.claudeSessionPercent,
            claudeSessionResetAt: SharedState.claudeSessionResetAt,
            claudeWeeklyPercent: SharedState.claudeWeeklyPercent,
            claudeWeeklyResetAt: SharedState.claudeWeeklyResetAt,
            claudeSonnetPercent: SharedState.claudeSonnetPercent,
            claudeExtraUsagePercent: SharedState.claudeExtraUsagePercent,
            claudeExtraUsageDollars: SharedState.claudeExtraUsageDollars,
            claudeExtraUsageLimit: SharedState.claudeExtraUsageLimit,
            codexSessionPercent: SharedState.codexSessionPercent,
            codexWeeklyPercent: SharedState.codexWeeklyPercent,
            apiSpendToday: SharedState.apiSpendToday,
            apiSpend7Day: SharedState.apiSpend7Day,
            apiSpend30Day: SharedState.apiSpend30Day
        )
        return FrankWidgetSnapshot(status: status, usage: usage, events: events)
    }
}

struct CalendarWidgetEvent: Identifiable {
    let id = UUID()
    let title: String
    let startTime: Date
    
    var timeUntilString: String {
        let interval = startTime.timeIntervalSince(Date())
        if interval <= 0 { return "now" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 {
            let remainingMinutes = minutes % 60
            return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
        }
        let days = hours / 24
        return "\(days)d"
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }
}

// MARK: - Widget Views

struct FrankWidgetView: View {
    let entry: FrankWidgetEntry
    @Environment(\.widgetFamily) private var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small

struct SmallWidgetView: View {
    let entry: FrankWidgetEntry
    
    var body: some View {
        UsageRingCard(
            title: "CLAUDE SESSION",
            percent: entry.snapshot.usage.claudeSessionPercent,
            subtitle: entry.snapshot.usage.countdownText(for: entry.snapshot.usage.claudeSessionResetAt)
        )
    }
}

// MARK: - Medium

struct MediumWidgetView: View {
    let entry: FrankWidgetEntry
    
    var body: some View {
        CombinedMediumView(snapshot: entry.snapshot)
    }
}

// MARK: - Large

struct LargeWidgetView: View {
    let entry: FrankWidgetEntry
    
    var body: some View {
        CombinedLargeView(snapshot: entry.snapshot)
    }
}

// MARK: - Cards / Components

private struct UsageRingCard: View {
    let title: String
    let percent: Double
    let subtitle: String
    var diameter: CGFloat = 110
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(percent / 100, 0), 1)))
                    .stroke(color(for: percent), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack {
                    Text("\(Int(percent.rounded()))%")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("utilized")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct UsageLinearCard: View {
    let title: String
    let percent: Double
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text("\(Int(percent.rounded()))%")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color(for: percent))
                Spacer()
            }
            ProgressView(value: max(0, min(percent / 100, 1)))
                .tint(color(for: percent))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct SpendCard: View {
    let usage: FrankWidgetSnapshot.UsageData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API SPEND")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(currency(usage.apiSpendToday))
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text("today")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                spendPill(label: "7d", value: usage.apiSpend7Day)
                spendPill(label: "30d", value: usage.apiSpend30Day)
            }
        }
        .padding()
    }
    
    private func spendPill(label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(currency(value))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(6)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusCard: View {
    let status: FrankWidgetSnapshot.StatusData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FRANK")
                    .font(.caption.weight(.semibold))
                Spacer()
                Circle()
                    .fill(status.isConnected ? Theme.success : Theme.error)
                    .frame(width: 10, height: 10)
            }
            Text(status.currentTask)
                .font(.headline.weight(.semibold))
                .lineLimit(2)
            Text("Model: \(status.modelDisplay)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Uptime \(status.uptimeString)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct CalendarCard: View {
    let events: [CalendarWidgetEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT EVENT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let next = events.first {
                Text(next.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                HStack {
                    Text(next.timeString)
                    Text("·")
                    Text(next.timeUntilString)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("No upcoming events")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private struct CombinedSmallCard: View {
    let snapshot: FrankWidgetSnapshot
    
    var body: some View {
        VStack(spacing: 8) {
            UsageRingCard(
                title: "SESSION",
                percent: snapshot.usage.claudeSessionPercent,
                subtitle: snapshot.usage.countdownText(for: snapshot.usage.claudeSessionResetAt)
            )
            Divider()
            HStack {
                Text("Weekly \(Int(snapshot.usage.claudeWeeklyPercent.rounded()))%")
                Spacer()
                Text(currency(snapshot.usage.apiSpendToday))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct SessionMediumView: View {
    let snapshot: FrankWidgetSnapshot
    
    var body: some View {
        HStack(spacing: 16) {
            UsageRingCard(
                title: "SESSION",
                percent: snapshot.usage.claudeSessionPercent,
                subtitle: snapshot.usage.countdownText(for: snapshot.usage.claudeSessionResetAt)
            )
            VStack(alignment: .leading, spacing: 8) {
                UsageLinearCard(
                    title: "WEEKLY",
                    percent: snapshot.usage.claudeWeeklyPercent,
                    subtitle: snapshot.usage.countdownText(for: snapshot.usage.claudeWeeklyResetAt)
                )
                SpendRow(usage: snapshot.usage)
            }
        }
        .padding()
    }
}

private struct WeeklyMediumView: View {
    let snapshot: FrankWidgetSnapshot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageLinearCard(
                title: "CLAUDE WEEKLY",
                percent: snapshot.usage.claudeWeeklyPercent,
                subtitle: snapshot.usage.countdownText(for: snapshot.usage.claudeWeeklyResetAt)
            )
            HStack {
                metricColumn(title: "Sonnet", value: snapshot.usage.claudeSonnetPercent)
                Spacer()
                metricColumn(title: "Extra", value: snapshot.usage.claudeExtraUsagePercent)
            }
        }
        .padding()
    }
    
    private func metricColumn(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))%")
                .font(.title3.weight(.bold))
                .foregroundStyle(color(for: value))
        }
    }
}

private struct SpendMediumView: View {
    let usage: FrankWidgetSnapshot.UsageData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OPENAI API SPEND")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading) {
                    Text(currency(usage.apiSpendToday))
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                    Text("today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    spendRow(label: "7 DAY", value: usage.apiSpend7Day)
                    spendRow(label: "30 DAY", value: usage.apiSpend30Day)
                }
            }
        }
        .padding()
    }
    
    private func spendRow(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(currency(value))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .padding(8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct StatusMediumView: View {
    let snapshot: FrankWidgetSnapshot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FRANK STATUS")
                    .font(.caption.weight(.semibold))
                Spacer()
                Circle()
                    .fill(snapshot.status.isConnected ? Theme.success : Theme.error)
                    .frame(width: 10, height: 10)
            }
            Text(snapshot.status.currentTask)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            HStack {
                Label(snapshot.status.modelDisplay, systemImage: "bolt.fill")
                Spacer()
                Label("\(snapshot.status.subAgentCount)", systemImage: "person.2.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
            HStack {
                VStack(alignment: .leading) {
                    Text("Session")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(snapshot.status.uptimeString)
                        .font(.headline)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Messages")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(snapshot.status.messagesToday)")
                        .font(.headline)
                        .monospacedDigit()
                }
            }
        }
        .padding()
    }
}

private struct CalendarMediumView: View {
    let events: [CalendarWidgetEvent]
    let status: FrankWidgetSnapshot.StatusData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CALENDAR")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(status.modelDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if events.isEmpty {
                Text("No upcoming events")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(events.prefix(3).enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(event.timeString) • \(event.timeUntilString)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if index != min(events.count, 3) - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding()
    }
}

private struct CombinedMediumView: View {
    let snapshot: FrankWidgetSnapshot
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                UsageLinearCard(
                    title: "SESSION",
                    percent: snapshot.usage.claudeSessionPercent,
                    subtitle: snapshot.usage.countdownText(for: snapshot.usage.claudeSessionResetAt)
                )
                UsageLinearCard(
                    title: "WEEKLY",
                    percent: snapshot.usage.claudeWeeklyPercent,
                    subtitle: snapshot.usage.countdownText(for: snapshot.usage.claudeWeeklyResetAt)
                )
            }
            SpendRow(usage: snapshot.usage)
        }
        .padding()
    }
}

private struct SpendRow: View {
    let usage: FrankWidgetSnapshot.UsageData
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("API Spend Today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(currency(usage.apiSpendToday))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .leading) {
                Text("7d")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(currency(usage.apiSpend7Day))
                    .font(.headline)
                    .monospacedDigit()
            }
            VStack(alignment: .leading) {
                Text("30d")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(currency(usage.apiSpend30Day))
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CombinedLargeView: View {
    let snapshot: FrankWidgetSnapshot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FRANK DASHBOARD")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.status.currentTask)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                }
                Spacer()
                Circle()
                    .fill(snapshot.status.isConnected ? Theme.success : Theme.error)
                    .frame(width: 12, height: 12)
            }
            
            HStack(spacing: 12) {
                UsageRingCard(
                    title: "SESSION",
                    percent: snapshot.usage.claudeSessionPercent,
                    subtitle: snapshot.usage.countdownText(for: snapshot.usage.claudeSessionResetAt)
                )
                UsageLinearCard(
                    title: "WEEKLY",
                    percent: snapshot.usage.claudeWeeklyPercent,
                    subtitle: snapshot.usage.countdownText(for: snapshot.usage.claudeWeeklyResetAt)
                )
            }
            
            HStack(spacing: 12) {
                UsageLinearCard(
                    title: "CODEX 5H",
                    percent: snapshot.usage.codexSessionPercent,
                    subtitle: "Rate limit"
                )
                UsageLinearCard(
                    title: "CODEX 7D",
                    percent: snapshot.usage.codexWeeklyPercent,
                    subtitle: "Rate limit"
                )
            }
            
            SpendRow(usage: snapshot.usage)
            
            CalendarMediumView(events: snapshot.events, status: snapshot.status)
        }
        .padding()
    }
}

// MARK: - Helpers

private func color(for percent: Double) -> Color {
    let normalized = percent / 100
    if normalized < 0.6 { return Theme.success }
    if normalized < 0.8 { return Theme.warning }
    return Theme.error
}

private func currency(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: value as NSNumber) ?? "$0.00"
}

// MARK: - Preview

#if DEBUG
struct FrankWidgets_Previews: PreviewProvider {
    static var previews: some View {
        let entry = FrankWidgetEntry(date: Date(), snapshot: .placeholder)
        Group {
            FrankWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            FrankWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            FrankWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif
