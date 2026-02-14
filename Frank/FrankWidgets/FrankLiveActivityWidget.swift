import WidgetKit
import SwiftUI
import ActivityKit

/// Main widget extension for Frank Live Activities
/// Note: This file needs to be part of a separate Widget Extension target
struct FrankLiveActivityWidget: Widget {
    let kind: String = "FrankLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FrankActivityAttributes.self) { context in
            // Lock screen view
            LockScreenActivityView(context: context)
        } dynamicIsland: { context in
            // Dynamic Island views
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Text("🦞")
                            .font(.caption2)
                        Circle()
                            .fill(context.state.isConnected ? .green : .red)
                            .frame(width: 5, height: 5)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.compactTask)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundColor(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.uptimeString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Label(context.state.modelName.components(separatedBy: "/").last ?? "—", systemImage: "cpu")
                        if context.state.subAgentCount > 0 {
                            Label("\(context.state.subAgentCount) agents", systemImage: "brain.head.profile")
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            } compactLeading: {
                // Leading compact view (🦞 + connection dot)
                HStack(spacing: 2) {
                    Text(context.state.statusEmoji)
                        .font(.caption2)
                    Circle()
                        .fill(context.state.isConnected ? .green : .red)
                        .frame(width: 6, height: 6)
                }
            } compactTrailing: {
                // Trailing compact view (task snippet)
                Text(context.state.compactTask)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .lineLimit(1)
            } minimal: {
                // Minimal view
                Text(context.state.statusEmoji)
                    .font(.caption2)
            }
        }
    }
}

/// Lock screen Live Activity view
struct LockScreenActivityView: View {
    let context: ActivityViewContext<FrankActivityAttributes>
    
    var body: some View {
        HStack(spacing: 12) {
            // Left: Frank identity
            HStack(spacing: 6) {
                Text("🦞")
                    .font(.title3)
                Circle()
                    .fill(context.state.isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
            }
            
            // Center: Task
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.currentTask)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(context.state.modelName.components(separatedBy: "/").last ?? "—")
                    if context.state.subAgentCount > 0 {
                        Text("·")
                        Text("\(context.state.subAgentCount) agents")
                    }
                    Text("·")
                    Text(context.state.uptimeString)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
    }
}

/// Dynamic Island expanded view
struct DynamicIslandExpandedView: View {
    let context: ActivityViewContext<FrankActivityAttributes>
    
    var body: some View {
        HStack(spacing: 12) {
            // Leading side - Frank status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("🦞")
                        .font(.caption)
                    Circle()
                        .fill(context.state.isConnected ? .green : .red)
                        .frame(width: 6, height: 6)
                }
                Text("Frank")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.orange)
            }
            
            Spacer()
            
            // Center - Current task (truncated)
            VStack(alignment: .center, spacing: 2) {
                Text(context.state.compactTask)
                    .font(.caption2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                if context.state.subAgentCount > 0 {
                    Text("\(context.state.subAgentCount) agents")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            
            Spacer()
            
            // Trailing side - Model and uptime
            VStack(alignment: .trailing, spacing: 2) {
                Text(context.state.modelName.components(separatedBy: "/").last ?? context.state.modelName)
                    .font(.caption2)
                    .lineLimit(1)
                Text(context.state.uptimeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Widget bundle to include all Frank widgets
/// NOTE: Add @main when this file is moved to the FrankLiveActivity widget extension target
/// @main
struct FrankWidgetBundle: WidgetBundle {
    var body: some Widget {
        FrankLiveActivityWidget()
    }
}