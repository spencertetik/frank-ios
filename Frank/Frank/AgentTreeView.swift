import SwiftUI

struct AgentTreeView: View {
    @Environment(GatewayClient.self) private var gateway
    @State private var animateHierarchy = false
    
    private var sessions: [GatewayClient.ActiveSession] {
        if !gateway.activeSessionsSnapshot.isEmpty {
            return gateway.activeSessionsSnapshot
        }
        return gateway.activeAgents.map { GatewayClient.ActiveSession(agentInfo: $0) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    hierarchy
                }
                .padding()
            }
            .background(Theme.bgPrimary.ignoresSafeArea())
            .navigationTitle("Agents")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            gateway.fetchActiveSessions()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!gateway.isConnected)
                }
            }
            .refreshable { gateway.fetchActiveSessions() }
        }
        .task {
            gateway.fetchActiveSessions()
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: sessions.map { $0.key })
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Hierarchy")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Frank orchestrates a network of specialized workers. Track who's online, their models, and what they're handling in real-time.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
    }
    
    // MARK: - Tree
    
    private var hierarchy: some View {
        VStack(alignment: .leading, spacing: 18) {
            AgentNodeCard(
                name: "Frank",
                model: gateway.modelName,
                detail: gateway.currentTask,
                role: roleInfo(for: gateway.modelName),
                isActive: gateway.isConnected,
                subtitle: gateway.isConnected ? "Online" : "Offline",
                lastUpdated: gateway.sessionUptime > 0 ? Date().addingTimeInterval(-gateway.sessionUptime) : nil,
                isRoot: true
            )
            .accessibilityLabel("Frank main agent, currently \(gateway.isConnected ? "online" : "offline")")
            
            // Sort: active first, then by most recent
            let sorted = sessions.sorted { a, b in
                if a.isActive != b.isActive { return a.isActive }
                return a.updatedAt > b.updatedAt
            }
            
            if sorted.isEmpty {
                emptyState
            } else {
                let activeSessions = sorted
                let activeCount = activeSessions.filter(\.isActive).count
                
                HStack(spacing: 12) {
                    Label("\(activeCount) active", systemImage: "circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                    Label("\(activeSessions.count - activeCount) idle", systemImage: "circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.gray)
                }
                .padding(.leading, 28)
                VStack(alignment: .leading, spacing: 12) {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 2, height: 18)
                        .padding(.leading, 24)
                        .padding(.bottom, 4)
                    ForEach(Array(activeSessions.enumerated()), id: \.element.id) { index, session in
                        AgentBranchRow(
                            session: session,
                            isLast: index == activeSessions.count - 1,
                            role: roleInfo(for: session.model)
                        )
                        .opacity(session.isActive ? 1.0 : 0.5)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No agents working", systemImage: "moon.zzz")
                .font(.headline)
            Text("Frank is idle for now. As new sub-agents spin up, they will appear here with their current assignments.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding()
        .glassCard(cornerRadius: 14)
        .padding(.leading, 8)
    }
    
    // MARK: - Role Helpers
    
    private func roleInfo(for model: String) -> AgentRole {
        let lower = model.lowercased()
        if lower.contains("opus") {
            return AgentRole(label: "Project Manager", emoji: "🧠")
        } else if lower.contains("codex") || lower.contains("gpt-5.1") {
            return AgentRole(label: "Coding Agent", emoji: "💻")
        } else if lower.contains("kimi") {
            return AgentRole(label: "Vision", emoji: "👁")
        } else if lower.contains("grok") {
            return AgentRole(label: "Search & Intel", emoji: "🔍")
        } else if lower.contains("sonnet") {
            return AgentRole(label: "Fast Worker", emoji: "⚡")
        } else {
            return AgentRole(label: "Agent", emoji: "🤖")
        }
    }
}

// MARK: - Components

private struct AgentRole {
    let label: String
    let emoji: String
}

private struct AgentNodeCard: View {
    let name: String
    let model: String
    let detail: String
    let role: AgentRole
    let isActive: Bool
    var subtitle: String?
    var lastUpdated: Date?
    var isRoot: Bool = false
    
    private var statusColor: Color { isActive ? .green : .gray }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.title3.weight(.semibold))
                        statusDot
                        Spacer()
                        roleBadge
                    }
                    Text(model.isEmpty ? "Unknown model" : model)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(detail.isEmpty ? "Idle" : detail)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isActive ? .green.opacity(0.8) : Theme.textTertiary)
            }
            if let lastUpdated {
                Text("Updated \(relativeString(since: lastUpdated))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.cardBackground.opacity(isRoot ? 0.8 : 0.5), Theme.cardBackground.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: isRoot ? 20 : 16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: isRoot ? 20 : 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var statusDot: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(isActive ? "Active" : "Idle")
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor)
        }
    }
    
    private var roleBadge: some View {
        HStack(spacing: 6) {
            Text(role.emoji)
            Text(role.label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.cardBackground.opacity(0.7), in: Capsule())
    }
    
    private func relativeString(since date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct AgentBranchRow: View {
    let session: GatewayClient.ActiveSession
    let isLast: Bool
    let role: AgentRole
    
    private var lineColor: Color { Color.white.opacity(0.15) }
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            BranchConnector(isLast: isLast, lineColor: lineColor)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("\(session.kindEmoji) \(session.label)")
                                .font(.title3.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(session.kindLabel)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(kindColor(session.kind).opacity(0.2), in: Capsule())
                                .foregroundStyle(kindColor(session.kind))
                        }
                        HStack(spacing: 8) {
                            Circle()
                                .fill(session.isActive ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(session.model)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Text("·")
                                .foregroundStyle(Theme.textTertiary)
                            Text(session.tokenDisplay)
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                if !session.lastMessage.isEmpty {
                    Text(session.lastMessage)
                        .font(.callout)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
                Text(relativeString(since: session.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Theme.cardBackground.opacity(0.5), Theme.cardBackground.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.leading, 8)
    }
    
    private func kindColor(_ kind: GatewayClient.SessionKind) -> Color {
        switch kind {
        case .main: return .blue
        case .subagent: return .orange
        case .cron: return .purple
        case .group: return .cyan
        case .other: return .gray
        }
    }
    
    private func relativeString(since date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct BranchConnector: View {
    let isLast: Bool
    let lineColor: Color
    
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(lineColor)
                .frame(width: 2, height: 10)
            Circle()
                .fill(lineColor)
                .frame(width: 10, height: 10)
            Rectangle()
                .fill(lineColor)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .opacity(isLast ? 0 : 1)
            Spacer(minLength: 0)
        }
        .frame(width: 18)
    }
}

extension GatewayClient.ActiveSession {
    init(agentInfo: GatewayClient.AgentInfo) {
        self.init(
            key: agentInfo.id,
            model: agentInfo.model ?? "Unknown",
            label: agentInfo.name,
            updatedAt: Date(),
            lastMessage: agentInfo.status.capitalized,
            isActive: agentInfo.status.lowercased() != "completed",
            kind: .other,
            totalTokens: 0
        )
    }
    
    var kindEmoji: String {
        switch kind {
        case .main: return "🏠"
        case .subagent: return "🔧"
        case .cron: return "⏰"
        case .group: return "👥"
        case .other: return "📎"
        }
    }
    
    var kindLabel: String {
        switch kind {
        case .main: return "Main"
        case .subagent: return "Sub-Agent"
        case .cron: return "Cron Job"
        case .group: return "Group"
        case .other: return "Session"
        }
    }
    
    var tokenDisplay: String {
        if totalTokens > 1_000_000 {
            return String(format: "%.1fM tokens", Double(totalTokens) / 1_000_000)
        } else if totalTokens > 1000 {
            return String(format: "%.1fK tokens", Double(totalTokens) / 1000)
        }
        return "\(totalTokens) tokens"
    }
}

#Preview {
    AgentTreeView()
        .environment(GatewayClient())
        .environment(FrankStatusModel())
        .preferredColorScheme(.dark)
}
