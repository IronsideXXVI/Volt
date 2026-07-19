import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct OpenAIUsagePayload: Decodable, Sendable {
    let planType: String?
    let accountEmail: String?
    let rateLimit: RateLimit?
    let codeReviewRateLimit: RateLimit?
    let additionalRateLimits: [AdditionalRateLimit]
    let credits: Credits?
    let spendControl: SpendControl?
    let individualLimit: IndividualLimit?
    let overageLimitReached: Bool?
    let rateLimitReachedType: String?
    let rateLimitResetCredits: JSONValue?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case email
        case accountEmail = "account_email"
        case userEmail = "user_email"
        case rateLimit = "rate_limit"
        case codeReviewRateLimit = "code_review_rate_limit"
        case codeReviewRateLimits = "code_review_rate_limits"
        case additionalRateLimits = "additional_rate_limits"
        case credits
        case spendControl = "spend_control"
        case individualLimit = "individual_limit"
        case individualLimitCamel = "individualLimit"
        case overageLimitReached = "overage_limit_reached"
        case rateLimitReachedType = "rate_limit_reached_type"
        case rateLimitResetCredits = "rate_limit_reset_credits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try? container.decodeIfPresent(String.self, forKey: .planType)
        accountEmail = (try? container.decodeIfPresent(String.self, forKey: .email))
            ?? (try? container.decodeIfPresent(String.self, forKey: .accountEmail))
            ?? (try? container.decodeIfPresent(String.self, forKey: .userEmail))
        rateLimit = try? container.decodeIfPresent(RateLimit.self, forKey: .rateLimit)

        if let limit = try? container.decodeIfPresent(RateLimit.self, forKey: .codeReviewRateLimit) {
            codeReviewRateLimit = limit
        } else if let limit = try? container.decodeIfPresent(RateLimit.self, forKey: .codeReviewRateLimits) {
            codeReviewRateLimit = limit
        } else if let limits = try? container.decodeIfPresent(
            [LossyDecodable<RateLimit>].self,
            forKey: .codeReviewRateLimits
        ) {
            codeReviewRateLimit = limits.compactMap(\.value).first
        } else {
            codeReviewRateLimit = nil
        }

        additionalRateLimits = (try? container.decodeIfPresent(
            [LossyDecodable<AdditionalRateLimit>].self,
            forKey: .additionalRateLimits
        ))?.compactMap(\.value) ?? []
        credits = try? container.decodeIfPresent(Credits.self, forKey: .credits)
        spendControl = try? container.decodeIfPresent(SpendControl.self, forKey: .spendControl)
        individualLimit = (try? container.decodeIfPresent(IndividualLimit.self, forKey: .individualLimit))
            ?? (try? container.decodeIfPresent(IndividualLimit.self, forKey: .individualLimitCamel))
        overageLimitReached = container.flexibleBool(forKey: .overageLimitReached)
        rateLimitReachedType = Self.decodeReachedType(container: container)
        rateLimitResetCredits = try? container.decodeIfPresent(JSONValue.self, forKey: .rateLimitResetCredits)
    }

    private static func decodeReachedType(
        container: KeyedDecodingContainer<CodingKeys>
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: .rateLimitReachedType) {
            return value
        }
        if let object = try? container.decodeIfPresent([String: String].self, forKey: .rateLimitReachedType) {
            return object["type"]
        }
        return nil
    }

    struct RateLimit: Decodable, Sendable {
        let allowed: Bool?
        let limitReached: Bool?
        let primaryWindow: Window?
        let secondaryWindow: Window?
        let individualLimit: IndividualLimit?

        enum CodingKeys: String, CodingKey {
            case allowed
            case limitReached = "limit_reached"
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
            case individualLimit = "individual_limit"
            case individualLimitCamel = "individualLimit"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            allowed = container.flexibleBool(forKey: .allowed)
            limitReached = container.flexibleBool(forKey: .limitReached)
            primaryWindow = try? container.decodeIfPresent(Window.self, forKey: .primaryWindow)
            secondaryWindow = try? container.decodeIfPresent(Window.self, forKey: .secondaryWindow)
            individualLimit = (try? container.decodeIfPresent(IndividualLimit.self, forKey: .individualLimit))
                ?? (try? container.decodeIfPresent(IndividualLimit.self, forKey: .individualLimitCamel))
        }
    }

    struct Window: Decodable, Sendable {
        let usedPercent: Double?
        let resetAt: Date?
        let resetAfterSeconds: TimeInterval?
        let duration: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case resetsAt = "resets_at"
            case resetAfterSeconds = "reset_after_seconds"
            case duration = "limit_window_seconds"
            case windowMinutes = "window_minutes"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = container.flexibleDouble(forKey: .usedPercent)
            resetAt = container.flexibleDate(forKey: .resetAt)
                ?? container.flexibleDate(forKey: .resetsAt)
            resetAfterSeconds = container.flexibleDouble(forKey: .resetAfterSeconds)
            duration = container.flexibleDouble(forKey: .duration)
                ?? container.flexibleDouble(forKey: .windowMinutes).map { $0 * 60 }
        }

        func resolvedResetDate(now: Date) -> Date? {
            if let resetAt { return resetAt }
            guard let resetAfterSeconds, resetAfterSeconds > 0 else { return nil }
            return now.addingTimeInterval(resetAfterSeconds)
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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try? container.decodeIfPresent(String.self, forKey: .name)
            feature = try? container.decodeIfPresent(String.self, forKey: .feature)
            rateLimit = try? container.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
        }
    }

    struct Credits: Decodable, Sendable {
        let hasCredits: Bool
        let unlimited: Bool
        let balance: String?
        let approximateLocalMessages: [JSONValue]
        let approximateCloudMessages: [JSONValue]

        enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
            case unlimited
            case balance
            case approximateLocalMessages = "approx_local_messages"
            case approximateCloudMessages = "approx_cloud_messages"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasCredits = container.flexibleBool(forKey: .hasCredits) ?? false
            unlimited = container.flexibleBool(forKey: .unlimited) ?? false
            balance = container.flexibleString(forKey: .balance)
            approximateLocalMessages = (try? container.decodeIfPresent(
                [JSONValue].self,
                forKey: .approximateLocalMessages
            )) ?? []
            approximateCloudMessages = (try? container.decodeIfPresent(
                [JSONValue].self,
                forKey: .approximateCloudMessages
            )) ?? []
        }
    }

    struct SpendControl: Decodable, Sendable {
        let reached: Bool?
        let individualLimit: IndividualLimit?

        enum CodingKeys: String, CodingKey {
            case reached
            case individualLimit = "individual_limit"
            case individualLimitCamel = "individualLimit"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            reached = container.flexibleBool(forKey: .reached)
            individualLimit = (try? container.decodeIfPresent(IndividualLimit.self, forKey: .individualLimit))
                ?? (try? container.decodeIfPresent(IndividualLimit.self, forKey: .individualLimitCamel))
        }
    }

    struct IndividualLimit: Decodable, Sendable {
        let source: String?
        let limit: String?
        let used: String?
        let remaining: String?
        let usedPercent: Double?
        let remainingPercent: Double?
        let resetAt: Date?
        let resetAfterSeconds: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case source
            case limit
            case used
            case remaining
            case usedPercent = "used_percent"
            case usedPercentCamel = "usedPercent"
            case remainingPercent = "remaining_percent"
            case remainingPercentCamel = "remainingPercent"
            case resetAt = "reset_at"
            case resetsAt = "resets_at"
            case resetsAtCamel = "resetsAt"
            case resetAfterSeconds = "reset_after_seconds"
            case resetAfterSecondsCamel = "resetAfterSeconds"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            source = try? container.decodeIfPresent(String.self, forKey: .source)
            limit = container.flexibleString(forKey: .limit)
            used = container.flexibleString(forKey: .used)
            remaining = container.flexibleString(forKey: .remaining)
            usedPercent = container.flexibleDouble(forKey: .usedPercent)
                ?? container.flexibleDouble(forKey: .usedPercentCamel)
            remainingPercent = container.flexibleDouble(forKey: .remainingPercent)
                ?? container.flexibleDouble(forKey: .remainingPercentCamel)
            resetAt = container.flexibleDate(forKey: .resetAt)
                ?? container.flexibleDate(forKey: .resetsAt)
                ?? container.flexibleDate(forKey: .resetsAtCamel)
            resetAfterSeconds = container.flexibleDouble(forKey: .resetAfterSeconds)
                ?? container.flexibleDouble(forKey: .resetAfterSecondsCamel)
        }

        var derivedUsedPercent: Double? {
            if let usedPercent, usedPercent.isFinite { return usedPercent }
            if let remainingPercent, remainingPercent.isFinite { return 100 - remainingPercent }
            guard let limitValue = Self.numericAmount(limit), limitValue > 0 else { return nil }
            if let usedValue = Self.numericAmount(used) {
                return usedValue / limitValue * 100
            }
            if let remainingValue = Self.numericAmount(remaining) {
                return (1 - remainingValue / limitValue) * 100
            }
            return nil
        }

        func resolvedResetDate(now: Date) -> Date? {
            if let resetAt { return resetAt }
            guard let resetAfterSeconds, resetAfterSeconds > 0 else { return nil }
            return now.addingTimeInterval(resetAfterSeconds)
        }

        private static func numericAmount(_ value: String?) -> Double? {
            guard let value else { return nil }
            let allowed = value.filter { $0.isNumber || $0 == "." || $0 == "-" }
            return Double(allowed)
        }
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(Value.self)
    }
}

private enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var compactDescription: String? {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
        case let .bool(value):
            return value ? "Yes" : "No"
        case let .object(value):
            let preferredKeys = ["model", "name", "messages", "count", "value"]
            let parts = preferredKeys.compactMap { key -> String? in
                guard let description = value[key]?.compactDescription else { return nil }
                return key == "model" || key == "name" ? description : "\(key): \(description)"
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case let .array(value):
            let parts = value.compactMap(\.compactDescription)
            return parts.isEmpty ? nil : parts.prefix(3).joined(separator: ", ")
        case .null:
            return nil
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

    func flexibleBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value.rounded() == value ? String(Int(value)) : String(value)
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    func flexibleDate(forKey key: Key) -> Date? {
        if let epoch = flexibleDouble(forKey: key), epoch > 0 {
            return Date(timeIntervalSince1970: epoch > 10_000_000_000 ? epoch / 1000 : epoch)
        }
        if let raw = try? decodeIfPresent(String.self, forKey: key) {
            return ISO8601.date(from: raw)
        }
        return nil
    }
}

private enum OpenAIRequestError: Error {
    case unauthorized
    case rateLimited(Date?)
    case status(Int)
    case invalidResponse
}

enum OpenAIUsageNormalizer {
    static func snapshot(
        from data: Data,
        credentials: OpenAICredentials,
        now: Date = Date()
    ) throws -> ProviderUsageSnapshot {
        let payload: OpenAIUsagePayload
        do {
            payload = try JSONDecoder().decode(OpenAIUsagePayload.self, from: data)
        } catch {
            throw UsageServiceError.invalidResponse(.openAI)
        }

        var sections: [UsageSection] = []
        if let rateLimit = payload.rateLimit {
            let windows = normalizedWindows(
                from: rateLimit,
                idPrefix: "openai-plan",
                baseTitle: nil,
                sourceIdentifier: "rate_limit",
                now: now
            )
            if !windows.isEmpty {
                sections.append(UsageSection(
                    id: "openai-plan-limits",
                    title: "Plan usage limits",
                    subtitle: "Current Codex plan quotas",
                    windows: windows
                ))
            }
        }

        let additionalWindows = payload.additionalRateLimits.enumerated().flatMap { index, additional in
            let explicitName = nonEmpty(additional.name)
            let feature = nonEmpty(additional.feature)
            let baseName = explicitName ?? feature.map(readableName) ?? "Additional limit"
            guard let rateLimit = additional.rateLimit else { return [UsageWindow]() }
            let identity: String
            if let feature, let explicitName,
               feature.caseInsensitiveCompare(explicitName) != .orderedSame {
                identity = "\(feature)-\(explicitName)"
            } else {
                identity = feature ?? explicitName ?? "limit-\(index)"
            }
            let identitySlug = slug(identity)
            let stableIdentity = identitySlug.isEmpty ? "limit-\(index)" : identitySlug
            return normalizedWindows(
                from: rateLimit,
                idPrefix: "openai-feature-\(stableIdentity)",
                baseTitle: baseName,
                sourceIdentifier: feature ?? explicitName ?? identity,
                now: now
            )
        }
        if !additionalWindows.isEmpty {
            sections.append(UsageSection(
                id: "openai-model-limits",
                title: "Model & feature limits",
                windows: sortedByDuration(deduplicated(additionalWindows))
            ))
        }

        if let codeReview = payload.codeReviewRateLimit {
            let windows = normalizedWindows(
                from: codeReview,
                idPrefix: "openai-code-review",
                baseTitle: nil,
                sourceIdentifier: "code_review_rate_limit",
                now: now
            )
            if !windows.isEmpty {
                sections.append(UsageSection(
                    id: "openai-code-review-limits",
                    title: "Code review",
                    windows: windows
                ))
            }
        }

        let spend = payload.spendControl?.individualLimit
            ?? payload.rateLimit?.individualLimit
            ?? payload.individualLimit
        if let spend, let usedPercent = spend.derivedUsedPercent, usedPercent.isFinite {
            let amountDetail: String?
            if let remaining = nonEmpty(spend.remaining), let limit = nonEmpty(spend.limit) {
                amountDetail = "\(remaining) remaining of \(limit)"
            } else if let used = nonEmpty(spend.used), let limit = nonEmpty(spend.limit) {
                amountDetail = "\(used) used of \(limit)"
            } else {
                amountDetail = nil
            }
            let reached = payload.spendControl?.reached ?? (usedPercent >= 100 ? true : nil)
            let title = nonEmpty(spend.source).map(readableName) ?? "Workspace limit"
            sections.append(UsageSection(
                id: "openai-spend-control",
                title: "Spend control",
                windows: [UsageWindow(
                    id: "openai-spend-control-individual",
                    title: title,
                    usedPercent: usedPercent,
                    displayMode: .remaining,
                    resetsAt: spend.resolvedResetDate(now: now),
                    duration: nil,
                    sourceIdentifier: spend.source,
                    detail: amountDetail,
                    isAllowed: reached.map { !$0 },
                    isLimitReached: reached
                )]
            ))
        }

        var detailSections: [UsageDetailSection] = []
        if let credits = payload.credits {
            var items: [UsageDetailItem] = []
            let creditValue: String
            if credits.unlimited {
                creditValue = "Unlimited"
            } else if credits.hasCredits, let balance = nonEmpty(credits.balance) {
                creditValue = balance
            } else if credits.hasCredits {
                creditValue = "Available"
            } else {
                creditValue = "Not available"
            }
            items.append(UsageDetailItem(id: "openai-credit-balance", title: "Credits", value: creditValue))
            if let value = messageEstimate(credits.approximateLocalMessages) {
                items.append(UsageDetailItem(
                    id: "openai-local-message-estimate",
                    title: "Local message estimate",
                    value: value
                ))
            }
            if let value = messageEstimate(credits.approximateCloudMessages) {
                items.append(UsageDetailItem(
                    id: "openai-cloud-message-estimate",
                    title: "Cloud message estimate",
                    value: value
                ))
            }
            detailSections.append(UsageDetailSection(id: "openai-credits", title: "Credits", items: items))
        }

        let resetCreditItems = parseResetCredits(payload.rateLimitResetCredits)
        if !resetCreditItems.isEmpty {
            detailSections.append(UsageDetailSection(
                id: "openai-reset-credits",
                title: "Usage limit resets",
                items: resetCreditItems
            ))
        }

        var notices: [UsageNotice] = []
        if payload.rateLimit?.allowed == false || payload.rateLimit?.limitReached == true {
            notices.append(UsageNotice(
                id: "openai-plan-limit-reached",
                kind: .warning,
                message: "The current Codex plan limit has been reached."
            ))
        }
        let spendLimitReached = payload.spendControl?.reached == true
            || (spend?.derivedUsedPercent ?? 0) >= 100
        if spendLimitReached {
            notices.append(UsageNotice(
                id: "openai-spend-limit-reached",
                kind: .warning,
                message: "The account spend-control limit has been reached."
            ))
        }
        if payload.overageLimitReached == true {
            notices.append(UsageNotice(
                id: "openai-overage-limit-reached",
                kind: .warning,
                message: "The account overage limit has been reached."
            ))
        }
        if let reachedType = nonEmpty(payload.rateLimitReachedType),
           !(reachedType.caseInsensitiveCompare("rate_limit_reached") == .orderedSame
             && (payload.rateLimit?.allowed == false || payload.rateLimit?.limitReached == true)) {
            notices.append(UsageNotice(
                id: "openai-reached-\(slug(reachedType))",
                kind: .warning,
                message: reachedTypeDescription(reachedType)
            ))
        }

        let rawPlan = nonEmpty(payload.planType) ?? nonEmpty(credentials.tokenPlan)
        return ProviderUsageSnapshot(
            provider: .openAI,
            account: nonEmpty(payload.accountEmail) ?? nonEmpty(credentials.accountEmail),
            plan: rawPlan.map(planDisplayName),
            sections: sections,
            detailSections: detailSections,
            notices: deduplicatedNotices(notices),
            updatedAt: now
        )
    }

    static func planDisplayName(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "prolite":
            return "Pro 5x"
        case "pro":
            return "Pro 20x"
        case "free_workspace":
            return "Free workspace"
        case "self_serve_business_usage_based":
            return "Business"
        case "enterprise_cbp_usage_based":
            return "Enterprise"
        default:
            return readableName(raw)
        }
    }

    private static func normalizedWindows(
        from rateLimit: OpenAIUsagePayload.RateLimit,
        idPrefix: String,
        baseTitle: String?,
        sourceIdentifier: String,
        now: Date
    ) -> [UsageWindow] {
        let candidates: [(String, OpenAIUsagePayload.Window?)] = [
            ("primary", rateLimit.primaryWindow),
            ("secondary", rateLimit.secondaryWindow),
        ]
        let available = candidates.compactMap { key, window -> (String, OpenAIUsagePayload.Window)? in
            guard let window, let used = window.usedPercent, used.isFinite else { return nil }
            return (key, window)
        }.sorted { left, right in
            switch (left.1.duration, right.1.duration) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs < rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return left.0 < right.0
            }
        }
        let semanticKeys = available.map { key, window in
            periodIdentifier(for: window.duration) ?? key
        }
        let keyCounts = Dictionary(grouping: semanticKeys, by: { $0 }).mapValues(\.count)

        return available.enumerated().map { index, candidate in
            let (key, window) = candidate
            let windowTitle = title(
                for: window.duration,
                fallback: key == "primary" ? "Current limit" : "Long-term limit"
            )
            let title: String
            if let baseTitle {
                let period = shortTitle(for: window.duration, fallback: "")
                title = period.isEmpty ? baseTitle : "\(baseTitle) · \(period)"
            } else {
                title = windowTitle
            }
            let statusDetail: String?
            if rateLimit.limitReached == true {
                statusDetail = "Limit reached"
            } else if rateLimit.allowed == false {
                statusDetail = "Currently unavailable"
            } else {
                statusDetail = nil
            }
            let semanticKey = semanticKeys[index]
            let idSuffix = keyCounts[semanticKey, default: 0] > 1
                ? "\(semanticKey)-\(key)"
                : semanticKey
            return UsageWindow(
                id: "\(idPrefix)-\(idSuffix)",
                title: title,
                usedPercent: window.usedPercent ?? 0,
                displayMode: .remaining,
                resetsAt: window.resolvedResetDate(now: now),
                duration: window.duration,
                sourceIdentifier: sourceIdentifier,
                detail: statusDetail,
                isAllowed: rateLimit.allowed,
                isLimitReached: rateLimit.limitReached
            )
        }
    }

    private static func title(for duration: TimeInterval?, fallback: String) -> String {
        let period = shortTitle(for: duration, fallback: "")
        guard !period.isEmpty else { return fallback }
        return "\(period) limit"
    }

    private static func shortTitle(for duration: TimeInterval?, fallback: String) -> String {
        guard let duration, duration > 0 else {
            return fallback == "primary" ? "Primary" : (fallback == "secondary" ? "Secondary" : fallback)
        }
        let hours = duration / (60 * 60)
        let days = duration / (24 * 60 * 60)
        if abs(hours - 5) < 0.01 { return "5-hour" }
        if abs(days - 1) < 0.01 { return "Daily" }
        if abs(days - 7) < 0.01 { return "Weekly" }
        if abs(days - 30) < 1 { return "Monthly" }
        if hours < 48 {
            return "\(formattedWholeNumber(hours))-hour"
        }
        return "\(formattedWholeNumber(days))-day"
    }

    private static func periodIdentifier(for duration: TimeInterval?) -> String? {
        guard let duration, duration > 0 else { return nil }
        return slug(shortTitle(for: duration, fallback: "window"))
    }

    private static func formattedWholeNumber(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.01 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }

    private static func messageEstimate(_ values: [JSONValue]) -> String? {
        let descriptions = values.compactMap(\.compactDescription)
        guard !descriptions.isEmpty else { return nil }
        return descriptions.prefix(3).joined(separator: ", ")
    }

    private static func reachedTypeDescription(_ value: String) -> String {
        switch value.lowercased() {
        case "rate_limit_reached":
            return "The current rate limit has been reached."
        case "workspace_owner_credits_depleted":
            return "Workspace credits are depleted."
        case "workspace_member_credits_depleted":
            return "Your workspace credits are depleted."
        case "workspace_owner_usage_limit_reached":
            return "The workspace usage limit has been reached."
        case "workspace_member_usage_limit_reached":
            return "Your workspace usage limit has been reached."
        default:
            return "Usage is restricted: \(readableName(value))."
        }
    }

    private static func deduplicated(_ windows: [UsageWindow]) -> [UsageWindow] {
        var seen = Set<String>()
        return windows.filter { seen.insert($0.id).inserted }
    }

    private static func sortedByDuration(_ windows: [UsageWindow]) -> [UsageWindow] {
        windows.sorted { left, right in
            switch (left.duration, right.duration) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs < rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
        }
    }

    private static func deduplicatedNotices(_ notices: [UsageNotice]) -> [UsageNotice] {
        var seen = Set<String>()
        return notices.filter { seen.insert($0.message).inserted }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    // MARK: Reset credits

    /// Best-effort parse of the `rate_limit_reset_credits` payload into one row per
    /// available credit, showing the amount and its expiry. The shape is not
    /// contractually documented, so we defensively probe common key names.
    private static func parseResetCredits(_ value: JSONValue?) -> [UsageDetailItem] {
        guard let value else { return [] }

        let entries: [JSONValue]
        switch value {
        case let .array(array):
            entries = array
        case let .object(object):
            if let nested = ["credits", "items", "resets", "data", "balances", "reset_credits"]
                .lazy.compactMap({ object[$0] }).first,
               case let .array(array) = nested {
                entries = array
            } else {
                entries = [value]
            }
        default:
            entries = [value]
        }

        return entries.enumerated().compactMap { index, entry in
            resetCreditItem(entry, index: index)
        }
    }

    private static func resetCreditItem(_ value: JSONValue, index: Int) -> UsageDetailItem? {
        switch value {
        case let .object(object):
            let amount = firstNumber(object, keys: [
                "credits", "amount", "value", "count", "balance",
                "remaining", "granted", "granted_credits", "reset_credits",
            ])
            let label = firstString(object, keys: ["label", "name", "description", "type", "title"])
            let expiry = firstDate(object, keys: [
                "expires_at", "expiry", "exp", "expires", "expiration",
                "expire_at", "valid_until", "reset_at", "resets_at",
            ])
            guard amount != nil || label != nil || expiry != nil else { return nil }
            let title = label ?? amount.map(creditLabel) ?? "Reset credit \(index + 1)"
            let detail = expiry.map { "Expires \(formatExpiry($0))" } ?? "No expiration"
            return UsageDetailItem(id: "openai-reset-credit-\(index)", title: title, value: detail)
        case let .number(number):
            return UsageDetailItem(id: "openai-reset-credit-\(index)", title: creditLabel(number), value: "")
        case let .string(string):
            guard let trimmed = nonEmpty(string) else { return nil }
            return UsageDetailItem(id: "openai-reset-credit-\(index)", title: trimmed, value: "")
        default:
            return nil
        }
    }

    private static func firstNumber(_ object: [String: JSONValue], keys: [String]) -> Double? {
        for key in keys {
            switch object[key] {
            case let .number(value):
                return value
            case let .string(value):
                if let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return number }
            default:
                continue
            }
        }
        return nil
    }

    private static func firstString(_ object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if case let .string(value)? = object[key], let trimmed = nonEmpty(value) {
                return trimmed
            }
        }
        return nil
    }

    private static func firstDate(_ object: [String: JSONValue], keys: [String]) -> Date? {
        for key in keys {
            switch object[key] {
            case let .number(value):
                if let date = dateFromEpoch(value) { return date }
            case let .string(value):
                if let date = dateFromString(value) { return date }
            default:
                continue
            }
        }
        return nil
    }

    private static func dateFromEpoch(_ value: Double) -> Date? {
        guard value > 0 else { return nil }
        // Values large enough to be milliseconds since 1970 are scaled down.
        let seconds = value > 1_000_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    private static func dateFromString(_ value: String) -> Date? {
        guard let trimmed = nonEmpty(value) else { return nil }
        if let seconds = Double(trimmed) { return dateFromEpoch(seconds) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: trimmed)
    }

    private static func creditLabel(_ amount: Double) -> String {
        let number = formattedWholeNumber(amount)
        return amount == 1 ? "\(number) credit" : "\(number) credits"
    }

    private static func formatExpiry(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private static func slug(_ value: String) -> String {
        var result = ""
        var previousWasSeparator = false
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func readableName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in
                let value = String(word)
                let lower = value.lowercased()
                if ["ai", "api", "gpt", "oauth"].contains(lower) { return lower.uppercased() }
                if value.uppercased() == value && value.count > 1 { return value }
                return value.prefix(1).uppercased() + value.dropFirst()
            }
            .joined(separator: " ")
    }
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

        let data: Data
        do {
            data = try await requestUsage(credentials: credentials)
        } catch OpenAIRequestError.unauthorized where !credentials.refreshToken.isEmpty {
            credentials = try await refresh(credentials)
            do {
                data = try await requestUsage(credentials: credentials)
            } catch OpenAIRequestError.unauthorized {
                throw UsageServiceError.invalidCredentials(.openAI)
            } catch OpenAIRequestError.invalidResponse {
                throw UsageServiceError.invalidResponse(.openAI)
            } catch OpenAIRequestError.rateLimited(let retryAfter) {
                throw UsageServiceError.rateLimited(.openAI, retryAfter)
            } catch OpenAIRequestError.status(let status) {
                throw UsageServiceError.server(.openAI, status)
            }
        } catch OpenAIRequestError.unauthorized {
            throw UsageServiceError.invalidCredentials(.openAI)
        } catch OpenAIRequestError.invalidResponse {
            throw UsageServiceError.invalidResponse(.openAI)
        } catch OpenAIRequestError.rateLimited(let retryAfter) {
            throw UsageServiceError.rateLimited(.openAI, retryAfter)
        } catch OpenAIRequestError.status(let status) {
            throw UsageServiceError.server(.openAI, status)
        }

        let snapshot = try OpenAIUsageNormalizer.snapshot(from: data, credentials: credentials)
        return Result(snapshot: snapshot, credentials: credentials)
    }

    private static func requestUsage(credentials: OpenAICredentials) async throws -> Data {
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
            return data
        case 401, 403:
            throw OpenAIRequestError.unauthorized
        case 429:
            throw OpenAIRequestError.rateLimited(retryAfterDate(from: response))
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
            if response.statusCode == 429 {
                throw UsageServiceError.rateLimited(.openAI, retryAfterDate(from: response))
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

    private static func retryAfterDate(from response: HTTPURLResponse, now: Date = Date()) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        if let seconds = TimeInterval(value), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: value)
    }
}
