import SwiftUI

struct ClaudeUsageCard: View {
    @Environment(ClaudeUsageService.self) private var usageService
    
    private struct Meter: Identifiable {
        let id: String
        let title: String
        let utilization: Double
        let detail: String?
    }
    
    private var meters: [Meter] {
        var list: [Meter] = []
        if let window = usageService.fiveHour, let utilization = window.utilization {
            list.append(Meter(
                id: "five_hour",
                title: "Session (5h)",
                utilization: utilization,
                detail: countdownText(for: window.resetsAt)
            ))
        }
        if let window = usageService.sevenDay, let utilization = window.utilization {
            list.append(Meter(
                id: "seven_day",
                title: "Weekly (7d)",
                utilization: utilization,
                detail: countdownText(for: window.resetsAt)
            ))
        }
        if let window = usageService.sevenDaySonnet, let utilization = window.utilization {
            list.append(Meter(
                id: "seven_day_sonnet",
                title: "Sonnet Weekly",
                utilization: utilization,
                detail: countdownText(for: window.resetsAt)
            ))
        }
        if let extra = usageService.extraUsage,
           extra.isEnabled == true,
           let used = extra.usedCredits,
           let limit = extra.monthlyLimit,
           let utilization = extra.utilization {
            let usedDollars = used / 100
            let limitDollars = limit / 100
            let detail = String(format: "$%.2f / $%.2f", usedDollars, limitDollars)
            list.append(Meter(
                id: "extra_usage",
                title: "Extra Usage",
                utilization: utilization,
                detail: detail
            ))
        }
        return list
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            footer
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14)
    }
    
    private var header: some View {
        HStack {
            Label("CLAUDE USAGE", systemImage: "gauge.open.with.lines.needle.33percent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .labelStyle(.titleAndIcon)
            Spacer()
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
}
