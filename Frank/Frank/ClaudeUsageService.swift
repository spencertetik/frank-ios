import Foundation
import Observation

@Observable
@MainActor
final class ClaudeUsageService {
    struct UsageWindow: Decodable {
        let utilization: Double?
        let resetsAt: Date?
        
        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }
    
    struct ExtraUsage: Decodable {
        let isEnabled: Bool?
        let monthlyLimit: Double?
        let usedCredits: Double?
        let utilization: Double?
        
        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case monthlyLimit = "monthly_limit"
            case usedCredits = "used_credits"
            case utilization
        }
    }
    
    private struct UsageResponse: Decodable {
        let fiveHour: UsageWindow?
        let sevenDay: UsageWindow?
        let sevenDaySonnet: UsageWindow?
        let extraUsage: ExtraUsage?
        
        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDaySonnet = "seven_day_sonnet"
            case extraUsage = "extra_usage"
        }
    }
    
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    var sevenDaySonnet: UsageWindow?
    var extraUsage: ExtraUsage?
    var isLoading = false
    var lastError: String?
    var lastUpdated: Date?
    
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let decoder: JSONDecoder
    
    init() {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions.insert(.withFractionalSeconds)
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }
            if let date = isoFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
        }
        startAutoRefresh()
    }
    
    deinit {
        refreshTask?.cancel()
    }
    
    func refreshNow() {
        Task { await refreshUsage() }
    }
    
    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshUsage()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await self.refreshUsage()
            }
        }
    }
    
    private func refreshUsage() async {
        if isLoading { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        guard !Secrets.claudeOAuthToken.isEmpty else {
            lastError = "Missing Claude OAuth token"
            return
        }
        
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            lastError = "Invalid usage URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(Secrets.claudeOAuthToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                lastError = "HTTP \(httpResponse.statusCode): \(body)"
                return
            }
            let usage = try decoder.decode(UsageResponse.self, from: data)
            fiveHour = usage.fiveHour
            sevenDay = usage.sevenDay
            sevenDaySonnet = usage.sevenDaySonnet
            extraUsage = usage.extraUsage
            lastUpdated = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
