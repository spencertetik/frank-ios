import SwiftUI

struct CodexUsageCard: View {
    @Environment(CodexUsageService.self) private var usageService
    
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()
    
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "EEE"
        return formatter
    }()
    
    private struct Meter: Identifiable {
        let id: String
        let title: String
        let utilization: Double
        let detail: String?
    }
    
    private var meters: [Meter] {
        var list: [Meter] = []
        if let window = usageService.sessionWindow, let percent = window.usedPercent {
            list.append(Meter(
                id: "codex_session",
                title: "Session (5h)",
                utilization: percent,
                detail: countdownText(for: window.resetAt)
            ))
        }
        if let window = usageService.weeklyWindow, let percent = window.usedPercent {
            list.append(Meter(
                id: "codex_weekly",
                title: "Weekly",
                utilization: percent,
                detail: countdownText(for: window.resetAt)
            ))
        }
        if usageService.isCodeReviewAllowed,
           let codeReview = usageService.codeReviewWindow,
           let percent = codeReview.usedPercent {
            list.append(Meter(
                id: "codex_code_review",
                title: "Code Review",
                utilization: percent,
                detail: countdownText(for: codeReview.resetAt)
            ))
        }
        if let credits = usageService.creditsInfo,
           let percent = credits.usedPercent {
            var detail: String?
            if let remaining = credits.remaining, let total = credits.total {
                detail = String(format: "%.0f / %.0f credits left", remaining, total)
            }
            list.append(Meter(
                id: "codex_credits",
                title: "Credits",
                utilization: percent,
                detail: detail
            ))
        }
        return list
    }
    
    private var spendStats: (today: Double, sevenDay: Double, thirtyDay: Double) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sevenStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let thirtyStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let todayAmount = usageService.dailyCosts.first { calendar.isDate($0.date, inSameDayAs: today) }?.amount ?? 0
        let sevenTotal = usageService.dailyCosts.filter { $0.date >= sevenStart }.reduce(0) { $0 + $1.amount }
        let thirtyTotal = usageService.dailyCosts.filter { $0.date >= thirtyStart }.reduce(0) { $0 + $1.amount }
        return (todayAmount, sevenTotal, thirtyTotal)
    }
    
    private var recentSevenDayCosts: [CodexUsageService.DailyCost] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-6...0).compactMap { offset -> CodexUsageService.DailyCost? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            if let existing = usageService.dailyCosts.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
                return existing
            }
            return CodexUsageService.DailyCost(date: date, amount: 0)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            apiSpendSection
            footer
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14)
    }
    
    private var header: some View {
        HStack(spacing: 10) {
            Label("CODEX USAGE", systemImage: "terminal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .labelStyle(.titleAndIcon)
            Spacer()
            if let plan = usageService.planType?.capitalized, !plan.isEmpty {
                Text(plan)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            Button {
                usageService.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color.white.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if usageService.isLoading && usageService.lastUpdated == nil {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.accent)
                Text("Fetching usage…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if meters.isEmpty {
            Text("Usage data unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 12) {
                ForEach(meters) { meter in
                    usageMeter(meter)
                    if meter.id != meters.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.05))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var footer: some View {
        if let error = usageService.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        } else if let updated = usageService.lastUpdated {
            Text("Updated " + updated.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private func usageMeter(_ meter: Meter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(meter.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(meter.utilization.rounded()))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color(for: meter.utilization))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(for: meter.utilization))
                        .frame(width: max(0, geo.size.width * CGFloat(min(max(meter.utilization / 100, 0), 1))), height: 8)
                }
            }
            .frame(height: 8)
            if let detail = meter.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func color(for utilization: Double) -> Color {
        let fraction = utilization / 100
        if fraction < 0.6 { return .green }
        if fraction < 0.8 { return .yellow }
        return .red
    }
    
    private func countdownText(for date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return "Resets soon" }
        let minutes = seconds / 60
        if minutes < 60 {
            return "Resets in \(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            if remainingMinutes == 0 {
                return "Resets in \(hours)h"
            }
            return "Resets in \(hours)h \(remainingMinutes)m"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        if remainingHours == 0 {
            return "Resets in \(days)d"
        }
        return "Resets in \(days)d \(remainingHours)h"
    }
    
    @ViewBuilder
    private var apiSpendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .overlay(Color.white.opacity(0.05))
            Label("API SPEND", systemImage: "dollarsign.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .labelStyle(.titleAndIcon)
            if usageService.isLoading && usageService.dailyCosts.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.accent)
                    Text("Fetching spend…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let error = usageService.spendError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if usageService.dailyCosts.isEmpty {
                Text("Spend data unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                spendStatsRow
                spendChart
                if let updated = usageService.spendLastUpdated {
                    Text("Spend updated " + updated.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var spendStatsRow: some View {
        let stats = spendStats
        return HStack(spacing: 10) {
            spendStatBox(title: "Today", value: stats.today)
            spendStatBox(title: "7-Day", value: stats.sevenDay)
            spendStatBox(title: "30-Day", value: stats.thirtyDay)
        }
    }
    
    private func spendStatBox(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(currencyText(for: value))
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var spendChart: some View {
        let costs = recentSevenDayCosts
        let maxAmount = costs.map(\.amount).max() ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(costs) { cost in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Theme.accent.opacity(0.9), Theme.accent.opacity(0.5)], startPoint: .bottom, endPoint: .top))
                            .frame(height: barHeight(for: cost.amount, maxAmount: maxAmount))
                        Text(shortWeekday(for: cost.date))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 40)
        }
    }
    
    private func barHeight(for amount: Double, maxAmount: Double) -> CGFloat {
        guard maxAmount > 0 else { return 4 }
        let ratio = amount / maxAmount
        return max(4, CGFloat(ratio) * 40)
    }
    
    private func shortWeekday(for date: Date) -> String {
        let symbol = CodexUsageCard.weekdayFormatter.string(from: date)
        guard let first = symbol.first else { return "" }
        return String(first).uppercased()
    }
    
    private func currencyText(for amount: Double) -> String {
        CodexUsageCard.currencyFormatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}
