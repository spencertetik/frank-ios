import WidgetKit
import SwiftUI
import ActivityKit

/// Main widget extension for Frank Live Activities
/// Note: This file needs to be part of a separate Widget Extension target
struct FrankLiveActivityWidget: Widget {
    let kind: String = "FrankLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FrankActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusBadge(isConnected: context.state.isConnected)
                }
                DynamicIslandExpandedRegion(.center) {
                    SessionStack(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CodexStack(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BottomInfoRow(state: context.state)
                }
            } compactLeading: {
                StatusDot(isConnected: context.state.isConnected)
            } compactTrailing: {
                Text(context.state.claudeSessionDisplay)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                StatusDot(isConnected: context.state.isConnected)
            }
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenActivityView: View {
    let context: ActivityViewContext<FrankActivityAttributes>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(isConnected: context.state.isConnected)
                Spacer()
                Text(resetCountdown(for: context.state.claudeSessionResetAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Session")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(context.state.claudeSessionDisplay)
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(color(for: context.state.claudeSessionPercent))
                }
                ProgressView(value: max(0, min(context.state.claudeSessionPercent / 100, 1)))
                    .tint(color(for: context.state.claudeSessionPercent))
            }
            
            HStack(spacing: 8) {
                Text(context.state.displayModel)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("Weekly \(Int(context.state.claudeWeeklyPercent.rounded()))%")
                if context.state.subAgentCount > 0 {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Label("\(context.state.subAgentCount) agents", systemImage: "person.2.fill")
                        .font(.caption)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

// MARK: - Dynamic Island sections

struct StatusBadge: View {
    let isConnected: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Text("FRANK")
                .font(.caption.weight(.semibold))
            StatusDot(isConnected: isConnected)
        }
        .foregroundStyle(isConnected ? Theme.textPrimary : Theme.error)
    }
}

struct StatusDot: View {
    let isConnected: Bool
    
    var body: some View {
        Circle()
            .fill(isConnected ? Theme.success : Theme.error)
            .frame(width: 10, height: 10)
    }
}

struct SessionStack: View {
    let state: FrankActivityAttributes.ContentState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: max(0, min(state.claudeSessionPercent / 100, 1))) {
                Text(state.claudeSessionDisplay)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: state.claudeSessionPercent))
            }
            .progressViewStyle(.linear)
            .tint(color(for: state.claudeSessionPercent))
            
            HStack {
                Text("Weekly")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(state.claudeWeeklyPercent.rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: state.claudeWeeklyPercent))
            }
            ProgressView(value: max(0, min(state.claudeWeeklyPercent / 100, 1)))
                .progressViewStyle(.linear)
                .tint(color(for: state.claudeWeeklyPercent))
        }
    }
}

struct CodexStack: View {
    let state: FrankActivityAttributes.ContentState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Codex")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline) {
                Text("\(Int(state.codexSessionPercent.rounded()))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(for: state.codexSessionPercent))
                Text("5h")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BottomInfoRow: View {
    let state: FrankActivityAttributes.ContentState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label(state.displayModel, systemImage: "bolt.fill")
                    .font(.caption2)
                Text("·")
                Text(state.uptimeString)
                    .font(.caption2.monospacedDigit())
                if state.subAgentCount > 0 {
                    Text("·")
                    Label("\(state.subAgentCount) agents", systemImage: "person.2.fill")
                        .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
            
            Text(state.compactTask)
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

// MARK: - Helpers

private func color(for percent: Double) -> Color {
    let normalized = percent / 100
    if normalized < 0.6 { return Theme.success }
    if normalized < 0.8 { return Theme.warning }
    return Theme.error
}

private func resetCountdown(for date: Date?) -> String {
    guard let date else { return "–" }
    let interval = Int(date.timeIntervalSinceNow)
    if interval <= 0 { return "Resets soon" }
    let minutes = interval / 60
    if minutes < 60 {
        return "\(minutes)m"
    }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if hours < 24 {
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }
    let days = hours / 24
    let remainingHours = hours % 24
    if remainingHours == 0 {
        return "\(days)d"
    }
    return "\(days)d \(remainingHours)h"
}

/// Widget bundle to include all Frank widgets
/// NOTE: Add @main when this file is moved to the FrankLiveActivity widget extension target
/// @main
struct FrankWidgetBundle: WidgetBundle {
    var body: some Widget {
        FrankLiveActivityWidget()
    }
}
