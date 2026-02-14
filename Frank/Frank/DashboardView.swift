import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(GatewayClient.self) private var gateway
    @Environment(CalendarManager.self) private var calendar
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var navigateToCalendar = false
    @State private var navigateToChat = false
    
    // Goals — persisted in UserDefaults
    @AppStorage("goalToday") private var goalToday = ""
    @AppStorage("goalWeek") private var goalWeek = ""
    @AppStorage("goalTodayDate") private var goalTodayDate: Double = 0
    @AppStorage("goalWeekDate") private var goalWeekDate: Double = 0
    
    // Goal action plan steps (JSON arrays)
    @AppStorage("goalTodaySteps") private var goalTodayStepsJSON = "[]"
    @AppStorage("goalWeekSteps") private var goalWeekStepsJSON = "[]"
    @AppStorage("goalTodayCompleted") private var goalTodayCompletedJSON = "[]"
    @AppStorage("goalWeekCompleted") private var goalWeekCompletedJSON = "[]"
    
    @State private var editingDailyGoal = false
    @State private var editingWeeklyGoal = false
    @State private var dailyGoalDraft = ""
    @State private var weeklyGoalDraft = ""
    @State private var dailyGoalExpanded = false
    @State private var weeklyGoalExpanded = false

    private var uptimeText: String {
        guard gateway.sessionUptime > 1 else { return "—" }
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = gateway.sessionUptime >= 3600 ? [.hour, .minute] : [.minute, .second]
        return f.string(from: gateway.sessionUptime) ?? "—"
    }

    private var nextEventCountdown: String {
        guard let next = calendar.upcomingEvents.first else { return "—" }
        let mins = next.minutesUntil
        if mins < 0 { return "now" }
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        let rem = mins % 60
        if hours < 24 { return rem > 0 ? "\(hours)h \(rem)m" : "\(hours)h" }
        return "\(hours / 24)d \(hours % 24)h"
    }
    
    // MARK: - Step helpers
    
    private func steps(from json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }
    
    private func completed(from json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }
    
    private func toggleStep(_ step: String, completedJSON: Binding<String>) {
        var list = completed(from: completedJSON.wrappedValue)
        if list.contains(step) {
            list.removeAll { $0 == step }
        } else {
            list.append(step)
        }
        if let data = try? JSONEncoder().encode(list), let str = String(data: data, encoding: .utf8) {
            completedJSON.wrappedValue = str
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    
                    if !gateway.isConnected {
                        connectionBanner
                    }
                    
                    liveStatusCard
                    usageStatsCard
                    ClaudeUsageCard()
                    goalsSection
                    
                    if let next = calendar.upcomingEvents.first {
                        nextEventCard(next)
                    }
                    
                    QuickCommandsView(selectedTab: .constant(0))
                    systemSection
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationBarHidden(true)
            .refreshable { calendar.fetchEvents() }
        }
        .onAppear { checkGoalDates() }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    // Logo mark
                    HStack(spacing: 10) {
                        // Claw logo from app icon
                        Image("AppIconImage")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FRANK")
                                .font(.system(size: 28, weight: .black, design: .default))
                                .tracking(2)
                            
                            Text("AI OPERATOR")
                                .font(.system(size: 11, weight: .semibold, design: .default))
                                .tracking(3)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                
                Spacer()
                
                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(gateway.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                        .shadow(color: gateway.isConnected ? .green.opacity(0.6) : .red.opacity(0.6), radius: 4)
                    Text(gateway.isConnected ? "ONLINE" : "OFFLINE")
                        .font(.system(size: 10, weight: .bold, design: .default))
                        .tracking(1.5)
                        .foregroundStyle(gateway.isConnected ? .green : .red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
            }
            
            // Tagline bar
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(height: 2)
                
                Text(gateway.isConnected ? statusTagline : "Waiting for connection")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Rectangle()
                    .fill(Theme.accent.opacity(0.3))
                    .frame(height: 2)
            }
            .padding(.top, 14)
        }
    }
    
    private var statusTagline: String {
        let model = gateway.modelName.isEmpty ? "Unknown" : gateway.modelName
        let agents = gateway.activeSubAgentCount
        if agents > 0 {
            return "\(model) · \(agents) agent\(agents == 1 ? "" : "s") active · \(uptimeText) uptime"
        }
        return "\(model) · \(uptimeText) uptime"
    }
    
    // MARK: - Live Status
    
    private var liveStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LIVE STATUS", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(uptimeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(gateway.currentTask)
                .font(.body.weight(.medium))
                .lineLimit(3)
            
            if gateway.activeSubAgentCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Text("\(gateway.activeSubAgentCount) sub-agent\(gateway.activeSubAgentCount == 1 ? "" : "s") running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                Text(gateway.modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14)
    }
    
    // MARK: - Usage Stats
    
    private func formatTokens(_ count: Int) -> String {
        if count < 1_000 { return "\(count)" }
        if count < 1_000_000 {
            let k = Double(count) / 1_000
            return k >= 10 ? "\(Int(k))K" : String(format: "%.1fK", k)
        }
        let m = Double(count) / 1_000_000
        return m >= 10 ? "\(Int(m))M" : String(format: "%.1fM", m)
    }
    
    private func contextColor(_ fraction: Double) -> Color {
        if fraction < 0.6 { return .green }
        if fraction < 0.8 { return .yellow }
        return .red
    }
    
    private var usageStatsCard: some View {
        let fraction = gateway.contextMax > 0 ? Double(gateway.contextUsed) / Double(gateway.contextMax) : 0
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("USAGE", systemImage: "chart.bar.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                // Model pill
                Text(gateway.modelName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            
            // Context meter
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Context")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(formatTokens(gateway.contextUsed)) / \(formatTokens(gateway.contextMax))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\(Int(fraction * 100))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(contextColor(fraction))
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(contextColor(fraction))
                            .frame(width: max(0, geo.size.width * fraction))
                    }
                }
                .frame(height: 6)
            }
            
            // Token counters
            HStack(spacing: 10) {
                tokenBox(label: "Tokens In", value: gateway.tokensIn, icon: "arrow.down.circle")
                tokenBox(label: "Tokens Out", value: gateway.tokensOut, icon: "arrow.up.circle")
            }
            
            // Bottom row: uptime, sub-agents, compactions
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(uptimeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if gateway.activeSubAgentCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                        Text("\(gateway.activeSubAgentCount) agent\(gateway.activeSubAgentCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if gateway.compactions > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(gateway.compactions) compaction\(gateway.compactions == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14)
    }
    
    private func tokenBox(label: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(formatTokens(value))
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Goals
    
    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("GOALS", systemImage: "target")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            
            goalCard(
                label: "Today",
                icon: "sun.max",
                text: goalToday,
                placeholder: "What's your goal for today?",
                isEditing: $editingDailyGoal,
                draft: $dailyGoalDraft,
                isExpanded: $dailyGoalExpanded,
                stepsJSON: goalTodayStepsJSON,
                completedJSON: $goalTodayCompletedJSON,
                onSave: {
                    goalToday = dailyGoalDraft
                    goalTodayDate = Date().timeIntervalSince1970
                    editingDailyGoal = false
                }
            )
            
            goalCard(
                label: "This Week",
                icon: "calendar.badge.clock",
                text: goalWeek,
                placeholder: "What's your goal for the week?",
                isEditing: $editingWeeklyGoal,
                draft: $weeklyGoalDraft,
                isExpanded: $weeklyGoalExpanded,
                stepsJSON: goalWeekStepsJSON,
                completedJSON: $goalWeekCompletedJSON,
                onSave: {
                    goalWeek = weeklyGoalDraft
                    goalWeekDate = Date().timeIntervalSince1970
                    editingWeeklyGoal = false
                }
            )
        }
    }
    
    private func goalCard(
        label: String,
        icon: String,
        text: String,
        placeholder: String,
        isEditing: Binding<Bool>,
        draft: Binding<String>,
        isExpanded: Binding<Bool>,
        stepsJSON: String,
        completedJSON: Binding<String>,
        onSave: @escaping () -> Void
    ) -> some View {
        let allSteps = steps(from: stepsJSON)
        let done = completed(from: completedJSON.wrappedValue)
        let completedCount = allSteps.filter { done.contains($0) }.count
        let hasSteps = !allSteps.isEmpty && !text.isEmpty
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                
                if hasSteps && !isEditing.wrappedValue {
                    Text("\(completedCount)/\(allSteps.count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    if isEditing.wrappedValue {
                        onSave()
                    } else {
                        draft.wrappedValue = text
                        isEditing.wrappedValue = true
                    }
                } label: {
                    Text(isEditing.wrappedValue ? "Save" : (text.isEmpty ? "Set" : "Edit"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
            }
            
            if isEditing.wrappedValue {
                TextField(placeholder, text: draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { onSave() }
                
                if !text.isEmpty {
                    Button("Cancel") {
                        isEditing.wrappedValue = false
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if text.isEmpty {
                Text(placeholder)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                // Goal text + expand tap area
                HStack {
                    Text(text)
                        .font(.subheadline)
                        .lineLimit(isExpanded.wrappedValue ? nil : 4)
                    Spacer()
                    if hasSteps {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if hasSteps {
                        withAnimation(.spring(duration: 0.3)) {
                            isExpanded.wrappedValue.toggle()
                        }
                    }
                }
                
                // Progress bar
                if hasSteps {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.accent)
                                .frame(width: allSteps.isEmpty ? 0 : geo.size.width * CGFloat(completedCount) / CGFloat(allSteps.count), height: 3)
                        }
                    }
                    .frame(height: 3)
                }
                
                // Expanded checklist
                if isExpanded.wrappedValue && hasSteps {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(allSteps, id: \.self) { step in
                            let isDone = done.contains(step)
                            Button {
                                toggleStep(step, completedJSON: completedJSON)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isDone ? Theme.accent : .gray)
                                        .font(.body)
                                    Text(step)
                                        .font(.subheadline)
                                        .foregroundStyle(isDone ? .secondary : .primary)
                                        .strikethrough(isDone)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 12)
    }
    
    // MARK: - Next Event (clickable)
    
    private func nextEventCard(_ event: CalendarManager.CalendarEvent) -> some View {
        NavigationLink {
            CalendarView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("NEXT UP", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(event.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(event.relativeDay) · \(event.timeString)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(event.calendarName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(nextEventCountdown)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - System
    
    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SYSTEM", systemImage: "server.rack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 0) {
                infoRow("Model", gateway.modelName)
                Divider()
                infoRow("Gateway", gateway.isConnected ? "Online" : "Offline")
                Divider()
                infoRow("Uptime", uptimeText)
            }
            .padding(.vertical, 4)
            .glassCard(cornerRadius: 12)
        }
    }
    
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Connection Banner
    
    private var connectionBanner: some View {
        Button { gateway.reconnectIfNeeded() } label: {
            HStack {
                Image(systemName: "wifi.exclamationmark")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection Lost").font(.subheadline.weight(.semibold))
                    Text("Tap to reconnect").font(.caption).opacity(0.8)
                }
                Spacer()
                Image(systemName: "arrow.clockwise")
            }
            .foregroundStyle(.white)
            .padding()
            .background(.red, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helpers
    
    private func checkGoalDates() {
        let cal = Calendar.current
        if goalTodayDate > 0 {
            let goalDay = Date(timeIntervalSince1970: goalTodayDate)
            if !cal.isDateInToday(goalDay) {
                goalToday = ""
                goalTodayDate = 0
                goalTodayStepsJSON = "[]"
                goalTodayCompletedJSON = "[]"
            }
        }
        if goalWeekDate > 0 {
            let goalDate = Date(timeIntervalSince1970: goalWeekDate)
            let thisMonday = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            let goalMonday = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: goalDate)
            if thisMonday != goalMonday {
                goalWeek = ""
                goalWeekDate = 0
                goalWeekStepsJSON = "[]"
                goalWeekCompletedJSON = "[]"
            }
        }
    }
}
