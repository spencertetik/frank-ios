import WidgetKit
import SwiftUI

/// Frank Home Screen Widgets
/// Note: This file needs to be part of the same Widget Extension target as FrankLiveActivityWidget
struct FrankHomeWidget: Widget {
    let kind: String = "FrankHomeWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FrankWidgetProvider()) { entry in
            FrankWidgetView(entry: entry)
                .containerBackground(.thinMaterial, for: .widget)
        }
        .configurationDisplayName("Frank Status")
        .description("Keep track of Frank's status and your upcoming events")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget Provider

struct FrankWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FrankWidgetEntry {
        FrankWidgetEntry(
            date: Date(),
            isConnected: true,
            currentTask: "Analyzing data...",
            nextEvent: CalendarWidgetEvent(title: "Team Meeting", startTime: Date().addingTimeInterval(3600)),
            upcomingEvents: [],
            messagesCount: 12,
            lastMessage: "System ready for commands"
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (FrankWidgetEntry) -> ()) {
        let entry = FrankWidgetEntry(
            date: Date(),
            isConnected: true,
            currentTask: "Ready for commands",
            nextEvent: CalendarWidgetEvent(title: "Design Review", startTime: Date().addingTimeInterval(1800)),
            upcomingEvents: [],
            messagesCount: 8,
            lastMessage: "All systems operational"
        )
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<FrankWidgetEntry>) -> ()) {
        let currentDate = Date()
        
        // Read real data from App Groups shared storage
        let events = SharedState.upcomingEvents.prefix(3).map { dict in
            CalendarWidgetEvent(
                title: dict["title"] ?? "Event",
                startTime: ISO8601DateFormatter().date(from: dict["start"] ?? "") ?? currentDate
            )
        }
        
        let entry = FrankWidgetEntry(
            date: currentDate,
            isConnected: SharedState.isConnected,
            currentTask: SharedState.currentTask,
            nextEvent: events.first,
            upcomingEvents: events,
            messagesCount: SharedState.messagesToday,
            lastMessage: SharedState.lastMessage
        )
        
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Entry

struct FrankWidgetEntry: TimelineEntry {
    let date: Date
    let isConnected: Bool
    let currentTask: String
    let nextEvent: CalendarWidgetEvent?
    let upcomingEvents: [CalendarWidgetEvent]
    let messagesCount: Int
    let lastMessage: String
}

struct CalendarWidgetEvent {
    let title: String
    let startTime: Date
    
    var timeUntilString: String {
        let interval = startTime.timeIntervalSince(Date())
        if interval < 0 { return "now" }
        
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        }
        
        return "\(hours / 24)d"
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
    @Environment(\.widgetFamily) var family
    
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

// MARK: - Small Widget (Connection Status + Current Task)

struct SmallWidgetView: View {
    let entry: FrankWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with connection status
            HStack {
                Text("Frank 🦞")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.textPrimary)
                
                Spacer()
                
                Circle()
                    .fill(entry.isConnected ? Theme.success : Theme.error)
                    .frame(width: 8, height: 8)
            }
            
            Spacer()
            
            // Current task
            VStack(alignment: .leading, spacing: 2) {
                Text("Current Task")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                
                Text(entry.currentTask)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(Theme.paddingMedium)
    }
}

// MARK: - Medium Widget (Next Event + Status + Messages)

struct MediumWidgetView: View {
    let entry: FrankWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Frank 🦞")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textPrimary)
                    
                    Text(entry.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(entry.isConnected ? Theme.success : Theme.error)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(entry.messagesCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.accent)
                    
                    Text("messages today")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            
            // Next event
            if let nextEvent = entry.nextEvent {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(Theme.accent)
                            .font(.caption)
                        
                        Text("Next Event")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                        
                        Spacer()
                        
                        Text(nextEvent.timeUntilString)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.accent)
                    }
                    
                    Text(nextEvent.title)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                }
            } else {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(Theme.textTertiary)
                        .font(.caption)
                    
                    Text("No upcoming events")
                        .font(.caption)
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
        .padding(Theme.paddingMedium)
    }
}

// MARK: - Large Widget (Mini Dashboard)

struct LargeWidgetView: View {
    let entry: FrankWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Frank 🦞")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.textPrimary)
                    
                    Text("Your AI Operator")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Circle()
                        .fill(entry.isConnected ? Theme.success : Theme.error)
                        .frame(width: 12, height: 12)
                    
                    Text(entry.isConnected ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundColor(entry.isConnected ? Theme.success : Theme.error)
                }
            }
            
            // Stats row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.messagesCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.accent)
                    
                    Text("messages")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                
                Spacer()
                
                if let nextEvent = entry.nextEvent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(nextEvent.timeUntilString)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.accent)
                        
                        Text("next event")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            
            // Upcoming events
            VStack(alignment: .leading, spacing: 6) {
                Text("Upcoming Events")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .textCase(.uppercase)
                
                if entry.upcomingEvents.isEmpty {
                    Text("No events scheduled")
                        .font(.footnote)
                        .foregroundColor(Theme.textTertiary)
                        .italic()
                } else {
                    ForEach(Array(entry.upcomingEvents.prefix(3).enumerated()), id: \.offset) { index, event in
                        HStack {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 4, height: 4)
                            
                            Text(event.title)
                                .font(.footnote)
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(event.timeString)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Recent message preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Activity")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .textCase(.uppercase)
                
                Text(entry.lastMessage)
                    .font(.footnote)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
            }
        }
        .padding(Theme.paddingMedium)
    }
}

// MARK: - Preview

#if DEBUG
struct FrankWidgets_Previews: PreviewProvider {
    static var previews: some View {
        let sampleEntry = FrankWidgetEntry(
            date: Date(),
            isConnected: true,
            currentTask: "Processing morning reports and analyzing data trends",
            nextEvent: CalendarWidgetEvent(title: "Team Standup Meeting", startTime: Date().addingTimeInterval(1800)),
            upcomingEvents: [
                CalendarWidgetEvent(title: "Team Standup", startTime: Date().addingTimeInterval(1800)),
                CalendarWidgetEvent(title: "Design Review", startTime: Date().addingTimeInterval(3600)),
                CalendarWidgetEvent(title: "Client Call", startTime: Date().addingTimeInterval(7200))
            ],
            messagesCount: 24,
            lastMessage: "All systems operational. Ready for your next command."
        )
        
        Group {
            FrankWidgetView(entry: sampleEntry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            FrankWidgetView(entry: sampleEntry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            
            FrankWidgetView(entry: sampleEntry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif