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
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.compactTask)
                            .font(.caption2)
                            .lineLimit(1)
                        if context.state.subAgentCount > 0 {
                            Text("\(context.state.subAgentCount) agents")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.modelName.components(separatedBy: "/").last ?? context.state.modelName)
                            .font(.caption2)
                            .lineLimit(1)
                        Text(context.state.uptimeString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
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
        VStack(spacing: 12) {
            // Header with Frank status
            HStack {
                HStack(spacing: 6) {
                    Text("🦞")
                        .font(.title2)
                    Text("Frank")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.orange)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(context.state.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(context.state.isConnected ? "Online" : "Offline")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            
            // Current task
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Task")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(context.state.currentTask)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Status row
            HStack {
                // Model info
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(context.state.modelName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Sub-agents count
                if context.state.subAgentCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("\(context.state.subAgentCount)")
                            .font(.caption.weight(.medium))
                    }
                }
                
                Spacer()
                
                // Uptime
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(context.state.uptimeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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