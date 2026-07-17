import Foundation

private struct ClaudeUsageBucket: Decodable, Sendable {
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Double.self, forKey: .utilization) {
            utilization = value
        } else if let value = try? container.decode(Int.self, forKey: .utilization) {
            utilization = Double(value)
        } else if let value = try? container.decode(String.self, forKey: .utilization) {
            utilization = Double(value.replacingOccurrences(of: "%", with: "")) ?? 0
        } else {
            utilization = 0
        }
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
    }
}

private struct ClaudeExtraUsage: Decodable, Sendable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case currency
    }
}

private struct ClaudeUsagePayload: Decodable, Sendable {
    let fiveHour: ClaudeUsageBucket?
    let sevenDay: ClaudeUsageBucket?
    let sevenDayOpus: ClaudeUsageBucket?
    let sevenDaySonnet: ClaudeUsageBucket?
    let sevenDayOmelette: ClaudeUsageBucket?
    let sevenDayCowork: ClaudeUsageBucket?
    let sevenDayOAuthApps: ClaudeUsageBucket?
    let extraUsage: ClaudeExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOmelette = "seven_day_omelette"
        case sevenDayCowork = "seven_day_cowork"
        case sevenDayOAuthApps = "seven_day_oauth_apps"
        case extraUsage = "extra_usage"
    }
}

private struct ClaudeOrganization: Decodable, Sendable {
    let name: String?
    let rateLimitTier: String?

    enum CodingKeys: String, CodingKey {
        case name
        case rateLimitTier = "rate_limit_tier"
    }

    var email: String? {
        guard let name, !name.isEmpty else { return nil }
        if let range = name.range(of: "'s Organization") {
            return String(name[..<range.lowerBound])
        }
        return name
    }

    var plan: String? {
        guard let rateLimitTier, !rateLimitTier.isEmpty else { return nil }
        let cleaned = rateLimitTier
            .replacingOccurrences(of: "default_claude_", with: "")
            .replacingOccurrences(of: "default_", with: "")
        let formatted = cleaned
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        return formatted.isEmpty ? nil : "Claude \(formatted)"
    }
}

enum ClaudeUsageService {
    static func fetch(credentials: ClaudeCredentials) async throws -> ProviderUsageSnapshot {
        guard credentials.isComplete else {
            throw UsageServiceError.notConfigured(.anthropic)
        }

        let organizationID = credentials.organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let usageURL = URL(string: "https://claude.ai/api/organizations/\(organizationID)/usage") else {
            throw UsageServiceError.message("The Claude organization ID is not valid.")
        }

        async let organization = fetchOrganization(
            organizationID: organizationID,
            sessionKey: credentials.sessionKey
        )

        let request = authenticatedRequest(url: usageURL, sessionKey: credentials.sessionKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, provider: .anthropic)

        let payload: ClaudeUsagePayload
        do {
            payload = try decoder.decode(ClaudeUsagePayload.self, from: data)
        } catch {
            throw UsageServiceError.invalidResponse(.anthropic)
        }

        let account = await organization
        var windows: [UsageWindow] = []
        append(
            payload.fiveHour,
            id: "claude-session",
            title: "Current session",
            duration: 5 * 60 * 60,
            to: &windows
        )
        append(
            payload.sevenDay,
            id: "claude-weekly",
            title: "All models",
            duration: 7 * 24 * 60 * 60,
            to: &windows
        )
        append(
            payload.sevenDaySonnet,
            id: "claude-sonnet",
            title: "Sonnet only",
            duration: 7 * 24 * 60 * 60,
            to: &windows
        )
        append(
            payload.sevenDayOpus,
            id: "claude-opus",
            title: "Opus only",
            duration: 7 * 24 * 60 * 60,
            to: &windows
        )
        append(
            payload.sevenDayOmelette,
            id: "claude-design",
            title: "Claude Design",
            duration: 7 * 24 * 60 * 60,
            to: &windows
        )
        append(
            payload.sevenDayCowork,
            id: "claude-cowork",
            title: "Cowork",
            duration: 7 * 24 * 60 * 60,
            to: &windows
        )
        append(
            payload.sevenDayOAuthApps,
            id: "claude-oauth",
            title: "OAuth apps",
            duration: 7 * 24 * 60 * 60,
            to: &windows
        )

        var credits: [CreditSummary] = []
        if let extra = payload.extraUsage {
            let state: String
            if let enabled = extra.isEnabled {
                state = enabled ? "On" : "Off"
            } else {
                state = "Available"
            }
            credits.append(CreditSummary(title: "Extra usage", value: state, detail: nil))

            if let used = extra.usedCredits {
                let limit = extra.monthlyLimit.map { formatMoney($0, currency: extra.currency) } ?? "Unlimited"
                credits.append(
                    CreditSummary(
                        title: "Extra usage spent",
                        value: formatMoney(used, currency: extra.currency),
                        detail: "Limit \(limit)"
                    )
                )
            }
        }

        return ProviderUsageSnapshot(
            provider: .anthropic,
            account: account?.email,
            plan: account?.plan,
            windows: windows,
            credits: credits,
            updatedAt: Date()
        )
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }()

    private static func append(
        _ bucket: ClaudeUsageBucket?,
        id: String,
        title: String,
        duration: TimeInterval,
        to windows: inout [UsageWindow]
    ) {
        guard let bucket else { return }
        windows.append(
            UsageWindow(
                id: id,
                title: title,
                usedPercent: bucket.utilization,
                resetsAt: bucket.resetsAt,
                duration: duration
            )
        )
    }

    private static func authenticatedRequest(url: URL, sessionKey: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }

    private static func validate(response: URLResponse, provider: AIProvider) throws {
        guard let response = response as? HTTPURLResponse else {
            throw UsageServiceError.invalidResponse(provider)
        }
        switch response.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw UsageServiceError.invalidCredentials(provider)
        default:
            throw UsageServiceError.server(provider, response.statusCode)
        }
    }

    private static func fetchOrganization(organizationID: String, sessionKey: String) async -> ClaudeOrganization? {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(organizationID)") else { return nil }
        let request = authenticatedRequest(url: url, sessionKey: sessionKey)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200
        else {
            return nil
        }
        return try? JSONDecoder().decode(ClaudeOrganization.self, from: data)
    }

    private static func formatMoney(_ cents: Double, currency: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: cents / 100)) ?? String(format: "$%.2f", cents / 100)
    }
}
