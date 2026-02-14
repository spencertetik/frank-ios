import SwiftUI

// MARK: - Specialist Definition

private struct Specialist: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let role: String
    let modelKeywords: [String]
    let modelDisplay: String
    
    static let roster: [Specialist] = [
        Specialist(id: "rex", name: "Rex", emoji: "💻", role: "Lead Developer", modelKeywords: ["codex", "gpt-5.1"], modelDisplay: "Codex / GPT-5.1"),
        Specialist(id: "iris", name: "Iris", emoji: "👁", role: "Visual QA", modelKeywords: ["kimi"], modelDisplay: "Kimi"),
        Specialist(id: "scout", name: "Scout", emoji: "🔍", role: "Intel & Search", modelKeywords: ["grok"], modelDisplay: "Grok"),
        Specialist(id: "dash", name: "Dash", emoji: "⚡", role: "Fast Ops", modelKeywords: ["sonnet"], modelDisplay: "Sonnet"),
    ]
    
    func matches(_ model: String) -> Bool {
        let lower = model.lowercased()
        return modelKeywords.contains { lower.contains($0) }
    }
}

// MARK: - Main View

struct AgentTreeView: View {
    @Environment(GatewayClient.self) private var gateway
    
    private var sessions: [GatewayClient.ActiveSession] {
        if !gateway.activeSessionsSnapshot.isEmpty {
            return gateway.activeSessionsSnapshot
        }
        return gateway.activeAgents.map { GatewayClient.ActiveSession(agentInfo: $0) }
    }
    
    /// Match sessions to specialists; returns (matched dict, unmatched array)
    private var sessionMapping: ([String: [GatewayClient.ActiveSession]], [GatewayClient.ActiveSession]) {
        var matched: [String: [GatewayClient.ActiveSession]] = [:]
        var unmatched: [GatewayClient.ActiveSession] = []
        for session in sessions {
            if let spec = Specialist.roster.first(where: { $0.matches(session.model) }) {
                matched[spec.id, default: []].append(session)
            } else {
                // Skip sessions matching opus (that's Frank)
                if !session.model.lowercased().contains("opus") {
                    unmatched.append(session)
                }
            }
        }
        return (matched, unmatched)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Frank card
                    frankCard
                    
                    // Connecting line down from Frank
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 2, height: 28)
                    
                    // Horizontal branch line
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 2)
                        Spacer()
                    }
                    .padding(.horizontal, 40)
                    
                    // Specialists 2x2 grid
                    let mapping = sessionMapping
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Specialist.roster) { spec in
                            let matched = mapping.0[spec.id] ?? []
                            let active = matched.first(where: \.isActive)
                            SpecialistCard(specialist: spec, activeSession: active, allMatched: matched)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    
                    // Other sessions
                    let others = mapping.1
                    if !others.isEmpty {
                        otherSessionsSection(others)
                    }
                }
                .padding(.vertical)
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
        .task { gateway.fetchActiveSessions() }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: sessions.map { $0.key })
    }
    
    // MARK: - Frank Card
    
    private var frankCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("🧠 Frank")
                    .font(.title2.weight(.bold))
                Circle()
                    .fill(gateway.isConnected ? .green : .gray)
                    .frame(width: 10, height: 10)
                Spacer()
                Text("Project Manager")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.cardBackground.opacity(0.7), in: Capsule())
            }
            Text(gateway.modelName.isEmpty ? "Opus" : gateway.modelName)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(gateway.currentTask.isEmpty ? (gateway.isConnected ? "Online — Coordinating" : "Offline") : gateway.currentTask)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.cardBackground.opacity(0.8), Theme.cardBackground.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Other Sessions
    
    private func otherSessionsSection(_ others: [GatewayClient.ActiveSession]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Other Sessions")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal)
                .padding(.top, 20)
            
            ForEach(others, id: \.id) { session in
                OtherSessionRow(session: session)
                    .padding(.horizontal)
            }
        }
    }
}

// MARK: - Specialist Card

private struct SpecialistCard: View {
    let specialist: Specialist
    let activeSession: GatewayClient.ActiveSession?
    let allMatched: [GatewayClient.ActiveSession]
    
    private var isActive: Bool { activeSession != nil }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Vertical connector line from top
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 2, height: 10)
                .frame(maxWidth: .infinity, alignment: .center)
            
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(spacing: 6) {
                    Text(specialist.emoji)
                        .font(.title3)
                    Text(specialist.name)
                        .font(.headline.weight(.semibold))
                    Circle()
                        .fill(isActive ? .green : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Spacer()
                }
                
                // Role badge
                Text(specialist.role)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isActive ? Color.white.opacity(0.1) : Color.white.opacity(0.05), in: Capsule())
                    .foregroundStyle(isActive ? Theme.textPrimary : Theme.textTertiary)
                
                // Model
                Text(specialist.modelDisplay)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                
                // Status / task
                if let session = activeSession {
                    Text(session.lastMessage.isEmpty ? "Working..." : session.lastMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(session.tokenDisplay)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    Text("Standing by")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .italic()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Theme.cardBackground.opacity(isActive ? 0.6 : 0.3), Theme.cardBackground.opacity(isActive ? 0.3 : 0.15)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(isActive ? 0.1 : 0.05), lineWidth: 1)
            )
            .opacity(isActive ? 1.0 : 0.55)
        }
    }
}

// MARK: - Other Session Row

private struct OtherSessionRow: View {
    let session: GatewayClient.ActiveSession
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.isActive ? .green : .gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.kindEmoji) \(session.label)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.model)
                    Text("·")
                    Text(session.tokenDisplay)
                }
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(10)
        .glassCard(cornerRadius: 12)
        .opacity(session.isActive ? 1.0 : 0.5)
    }
}

// MARK: - Existing Extensions (kept)

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
