import Foundation

private struct OpenAIUsagePayload: Decodable, Sendable {
    let planType: String?
    let rateLimit: RateLimit?
    let additionalRateLimits: [AdditionalRateLimit]
    let credits: Credits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
        case credits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try? container.decodeIfPresent(String.self, forKey: .planType)
        rateLimit = try? container.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
        additionalRateLimits = (try? container.decodeIfPresent(
            [AdditionalRateLimit].self,
            forKey: .additionalRateLimits
        )) ?? []
        credits = try? container.decodeIfPresent(Credits.self, forKey: .credits)
    }

    struct RateLimit: Decodable, Sendable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable, Sendable {
        let usedPercent: Double
        let resetAt: Date?
        let duration: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case duration = "limit_window_seconds"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = container.flexibleDouble(forKey: .usedPercent) ?? 0

            if let epoch = container.flexibleDouble(forKey: .resetAt) {
                resetAt = Date(timeIntervalSince1970: epoch)
            } else if let value = try? container.decodeIfPresent(String.self, forKey: .resetAt) {
                resetAt = ISO8601.date(from: value)
            } else {
                resetAt = nil
            }

            duration = container.flexibleDouble(forKey: .duration)
        }
    }

    struct AdditionalRateLimit: Decodable, Sendable {
        let name: String?
        let feature: String?
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case name = "limit_name"
            case feature = "metered_feature"
            case rateLimit = "rate_limit"
        }
    }

    struct Credits: Decodable, Sendable {
        let hasCredits: Bool
        let unlimited: Bool
        let balance: Double?

        enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
            case unlimited
            case balance
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasCredits = (try? container.decode(Bool.self, forKey: .hasCredits)) ?? false
            unlimited = (try? container.decode(Bool.self, forKey: .unlimited)) ?? false
            balance = container.flexibleDouble(forKey: .balance)
        }
    }
}

private extension KeyedDecodingContainer {
    func flexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

private enum OpenAIRequestError: Error {
    case unauthorized
    case status(Int)
    case invalidResponse
}

enum OpenAIUsageService {
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    struct Result: Sendable {
        let snapshot: ProviderUsageSnapshot
        let credentials: OpenAICredentials
    }

    static func fetch(credentials originalCredentials: OpenAICredentials) async throws -> Result {
        guard originalCredentials.isComplete else {
            throw UsageServiceError.notConfigured(.openAI)
        }

        var credentials = originalCredentials
        if credentials.shouldRefresh {
            credentials = try await refresh(credentials)
        }

        let payload: OpenAIUsagePayload
        do {
            payload = try await requestUsage(credentials: credentials)
        } catch OpenAIRequestError.unauthorized where !credentials.refreshToken.isEmpty {
            credentials = try await refresh(credentials)
            do {
                payload = try await requestUsage(credentials: credentials)
            } catch OpenAIRequestError.unauthorized {
                throw UsageServiceError.invalidCredentials(.openAI)
            } catch OpenAIRequestError.invalidResponse {
                throw UsageServiceError.invalidResponse(.openAI)
            } catch OpenAIRequestError.status(let status) {
                throw UsageServiceError.server(.openAI, status)
            }
        } catch OpenAIRequestError.unauthorized {
            throw UsageServiceError.invalidCredentials(.openAI)
        } catch OpenAIRequestError.invalidResponse {
            throw UsageServiceError.invalidResponse(.openAI)
        } catch OpenAIRequestError.status(let status) {
            throw UsageServiceError.server(.openAI, status)
        }

        var windows: [UsageWindow] = []
        if let primary = payload.rateLimit?.primaryWindow {
            windows.append(makeWindow(primary, id: "openai-primary", fallbackTitle: "Current window"))
        }
        if let secondary = payload.rateLimit?.secondaryWindow {
            windows.append(makeWindow(secondary, id: "openai-secondary", fallbackTitle: "Long-term limit"))
        }

        for (index, additional) in payload.additionalRateLimits.enumerated() {
            let baseName = readableName(additional.name ?? additional.feature ?? "Additional limit")
            if let primary = additional.rateLimit?.primaryWindow {
                windows.append(
                    makeWindow(
                        primary,
                        id: "openai-additional-\(index)-primary",
                        fallbackTitle: baseName
                    )
                )
            }
            if let secondary = additional.rateLimit?.secondaryWindow {
                windows.append(
                    makeWindow(
                        secondary,
                        id: "openai-additional-\(index)-secondary",
                        fallbackTitle: "\(baseName) weekly"
                    )
                )
            }
        }

        var creditRows: [CreditSummary] = []
        if let credits = payload.credits, credits.hasCredits || credits.unlimited || credits.balance != nil {
            let value: String
            if credits.unlimited {
                value = "Unlimited"
            } else if let balance = credits.balance {
                value = String(format: "%.2f", balance)
            } else {
                value = "Available"
            }
            creditRows.append(CreditSummary(title: "Credits", value: value, detail: nil))
        }

        let plan = payload.planType ?? credentials.tokenPlan
        let snapshot = ProviderUsageSnapshot(
            provider: .openAI,
            account: credentials.accountEmail,
            plan: plan.map(readableName),
            windows: windows,
            credits: creditRows,
            updatedAt: Date()
        )
        return Result(snapshot: snapshot, credentials: credentials)
    }

    private static func requestUsage(credentials: OpenAICredentials) async throws -> OpenAIUsagePayload {
        var request = URLRequest(url: usageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Volt/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Volt", forHTTPHeaderField: "originator")
        if !credentials.accountID.isEmpty {
            request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw OpenAIRequestError.invalidResponse
        }
        switch response.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(OpenAIUsagePayload.self, from: data)
            } catch {
                throw OpenAIRequestError.invalidResponse
            }
        case 401, 403:
            throw OpenAIRequestError.unauthorized
        default:
            throw OpenAIRequestError.status(response.statusCode)
        }
    }

    private static func refresh(_ credentials: OpenAICredentials) async throws -> OpenAICredentials {
        guard !credentials.refreshToken.isEmpty else {
            throw UsageServiceError.invalidCredentials(.openAI)
        }

        var request = URLRequest(url: refreshURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "scope": "openid profile email",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UsageServiceError.invalidResponse(.openAI)
        }
        guard response.statusCode == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = payload["access_token"] as? String,
              !accessToken.isEmpty
        else {
            if response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403 {
                throw UsageServiceError.invalidCredentials(.openAI)
            }
            throw UsageServiceError.server(.openAI, response.statusCode)
        }

        return OpenAICredentials(
            accessToken: accessToken,
            refreshToken: (payload["refresh_token"] as? String) ?? credentials.refreshToken,
            idToken: (payload["id_token"] as? String) ?? credentials.idToken,
            accountID: credentials.accountID,
            lastRefresh: Date()
        )
    }

    private static func makeWindow(
        _ window: OpenAIUsagePayload.Window,
        id: String,
        fallbackTitle: String
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            title: title(for: window.duration, fallback: fallbackTitle),
            usedPercent: window.usedPercent,
            resetsAt: window.resetAt,
            duration: window.duration
        )
    }

    private static func title(for duration: TimeInterval?, fallback: String) -> String {
        guard let duration else { return fallback }
        if duration < 7 * 60 * 60 {
            return "Current session"
        }
        if duration < 36 * 60 * 60 {
            return "Daily limit"
        }
        if duration < 15 * 24 * 60 * 60 {
            return "Weekly limit"
        }
        return "Monthly limit"
    }

    private static func readableName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
