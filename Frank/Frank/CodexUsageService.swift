import Foundation
import Observation

@Observable
@MainActor
final class CodexUsageService {
    struct LimitWindow: Decodable {
        let usedPercent: Double?
        let limitWindowSeconds: TimeInterval?
        let resetAfterSeconds: TimeInterval?
        let resetAt: Date?
        
        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAfterSeconds = "reset_after_seconds"
            case resetAt = "reset_at"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
            limitWindowSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .limitWindowSeconds)
            resetAfterSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .resetAfterSeconds)
            if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .resetAt) {
                resetAt = Date(timeIntervalSince1970: timestamp)
            } else {
                resetAt = nil
            }
        }
    }
    
    struct RateLimit: Decodable {
        let primaryWindow: LimitWindow?
        let secondaryWindow: LimitWindow?
        
        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }
    
    struct CodeReviewRateLimit: Decodable {
        let allowed: Bool?
        let primaryWindow: LimitWindow?
        
        enum CodingKeys: String, CodingKey {
            case allowed
            case primaryWindow = "primary_window"
        }
    }
    
    struct CreditsInfo: Decodable {
        let usedPercent: Double?
        let remaining: Double?
        let total: Double?
        
        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case remaining
            case total
        }
    }
    
    struct DailyCost: Identifiable, Hashable {
        let date: Date
        let amount: Double
        var id: Date { date }
    }
    
    private struct UsageResponse: Decodable {
        let planType: String?
        let rateLimit: RateLimit?
        let codeReviewRateLimit: CodeReviewRateLimit?
        let credits: CreditsInfo?
        
        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case codeReviewRateLimit = "code_review_rate_limit"
            case credits
        }
    }
    
    private struct CostsResponse: Decodable {
        struct Bucket: Decodable {
            struct Result: Decodable {
                struct Amount: Decodable {
                    let value: String
                    let currency: String?
                }
                let amount: Amount
            }
            
            let startTime: TimeInterval
            let results: [Result]
            
            enum CodingKeys: String, CodingKey {
                case startTime = "start_time"
                case results
            }
        }
        
        let data: [Bucket]
        let hasMore: Bool?
        let nextPage: String?
        
        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
        }
    }
    
    var planType: String?
    var sessionWindow: LimitWindow?
    var weeklyWindow: LimitWindow?
    var codeReviewWindow: LimitWindow?
    var creditsInfo: CreditsInfo?
    var isCodeReviewAllowed = false
    var dailyCosts: [DailyCost] = []
    var spendError: String?
    var spendLastUpdated: Date?
    var isLoading = false
    var lastError: String?
    var lastUpdated: Date?
    
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let decoder = JSONDecoder()
    
    init() {
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
        spendError = nil
        defer { isLoading = false }
        
        await fetchUsageLimits()
        await fetchApiSpend()
    }
    
    private func fetchUsageLimits() async {
        guard !Secrets.codexOAuthToken.isEmpty else {
            lastError = "Missing Codex OAuth token"
            return
        }
        
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            lastError = "Invalid usage URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(Secrets.codexOAuthToken)", forHTTPHeaderField: "Authorization")
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
            planType = usage.planType
            sessionWindow = usage.rateLimit?.primaryWindow
            weeklyWindow = usage.rateLimit?.secondaryWindow
            codeReviewWindow = usage.codeReviewRateLimit?.primaryWindow
            isCodeReviewAllowed = usage.codeReviewRateLimit?.allowed ?? false
            creditsInfo = usage.credits
            lastUpdated = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    private func fetchApiSpend() async {
        guard !Secrets.openAIAdminKey.isEmpty else {
            spendError = "Missing OpenAI admin key"
            return
        }
        
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let todayUTCStart = utcCalendar.startOfDay(for: Date())
        guard let startUTCDate = utcCalendar.date(byAdding: .day, value: -29, to: todayUTCStart) else {
            spendError = "Failed to calculate date range"
            return
        }
        let startEpoch = Int(startUTCDate.timeIntervalSince1970)
        let endEpoch = Int(Date().timeIntervalSince1970)
        guard let url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(startEpoch)&end_time=\(endEpoch)&bucket_width=1d") else {
            spendError = "Invalid spend URL"
            return
        }
        
        do {
            // Fetch all pages
            var entriesByDay: [String: Double] = [:]
            var currentURL = url
            var pageCount = 0
            
            while pageCount < 10 { // safety limit
                pageCount += 1
                var request = URLRequest(url: currentURL)
                request.httpMethod = "GET"
                request.setValue("Bearer \(Secrets.openAIAdminKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    spendError = "Invalid response"
                    return
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? "<no body>"
                    spendError = "HTTP \(httpResponse.statusCode)"
                    print("[CodexSpend] Error: HTTP \(httpResponse.statusCode) - \(body.prefix(200))")
                    return
                }
                let costsResponse = try decoder.decode(CostsResponse.self, from: data)
                
                for bucket in costsResponse.data {
                    var bucketTotal = 0.0
                    for result in bucket.results {
                        if let value = Double(result.amount.value) {
                            bucketTotal += value
                        }
                    }
                    let bucketDate = Date(timeIntervalSince1970: bucket.startTime)
                    let dc = utcCalendar.dateComponents([.year, .month, .day], from: bucketDate)
                    let key = String(format: "%04d-%02d-%02d", dc.year ?? 0, dc.month ?? 0, dc.day ?? 0)
                    entriesByDay[key, default: 0] += bucketTotal
                }
                
                // Check for more pages
                if costsResponse.hasMore == true, let nextPage = costsResponse.nextPage,
                   let nextURL = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(startEpoch)&end_time=\(endEpoch)&bucket_width=1d&page=\(nextPage)") {
                    currentURL = nextURL
                } else {
                    break
                }
            }
            var entries: [DailyCost] = []
            var cursor = startUTCDate
            let localCalendar = Calendar.current
            while cursor <= todayUTCStart {
                let dc = utcCalendar.dateComponents([.year, .month, .day], from: cursor)
                let key = String(format: "%04d-%02d-%02d", dc.year ?? 0, dc.month ?? 0, dc.day ?? 0)
                let amount = entriesByDay[key] ?? 0
                let displayDate = localCalendar.date(from: dc) ?? cursor
                entries.append(DailyCost(date: displayDate, amount: amount))
                guard let next = utcCalendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            dailyCosts = entries
            spendLastUpdated = Date()
            let nonZero = entries.filter { $0.amount > 0 }
            print("[CodexSpend] Fetched \(entries.count) days, \(nonZero.count) with spend, total: $\(entries.reduce(0) { $0 + $1.amount })")
            if entries.isEmpty {
                spendError = "No spend data available"
            }
        } catch {
            spendError = error.localizedDescription
        }
    }
}
