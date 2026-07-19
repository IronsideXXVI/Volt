import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ClaudeAuxiliaryUsage: Sendable {
    var prepaidAmount: Double?
    var prepaidCurrency: String?
    var autoReloadEnabled: Bool?
    var pendingInvoiceAmount: Double?
    var purchasesResetAt: Date?
    var bundlePaidThisMonth: Double?
    var bundleMonthlyCap: Double?
    var bundleCurrency: String?
    var routineUsed: Int?
    var routineLimit: Int?

    static let empty = ClaudeAuxiliaryUsage()
}

private struct ClaudeAccountInfo: Sendable {
    let email: String?
    let plan: String?
}

private enum ClaudeOAuthRequestError: Error {
    case unauthorized
    case forbidden
    case rateLimited(Date?)
    case status(Int)
    case invalidResponse
}

enum ClaudeUsageNormalizer {
    private struct Bucket {
        let utilization: Double
        let resetsAt: Date?
    }

    static func snapshot(
        from data: Data,
        account: String?,
        plan: String?,
        auxiliary: ClaudeAuxiliaryUsage = .empty,
        now: Date = Date()
    ) throws -> ProviderUsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageServiceError.invalidResponse(.anthropic)
        }

        var consumedKeys = Set<String>()
        var sessionWindows: [UsageWindow] = []
        var weeklyWindows: [UsageWindow] = []
        var featureWindows: [UsageWindow] = []

        if let bucket = bucket(root["five_hour"]) {
            consumedKeys.insert("five_hour")
            sessionWindows.append(makeWindow(
                bucket,
                id: "claude-session",
                title: "Current session",
                duration: 5 * 60 * 60,
                sourceIdentifier: "five_hour"
            ))
        }

        if let bucket = bucket(root["seven_day"]) {
            consumedKeys.insert("seven_day")
            weeklyWindows.append(makeWindow(
                bucket,
                id: "claude-weekly-all-models",
                title: "All models",
                duration: 7 * 24 * 60 * 60,
                sourceIdentifier: "seven_day"
            ))
        }

        let scoped = scopedLimits(from: root["limits"])
        consumedKeys.insert("limits")
        weeklyWindows.append(contentsOf: scoped.weekly)
        featureWindows.append(contentsOf: scoped.other)

        let scopedIdentities = Set<String>(scoped.weekly.compactMap { window -> String? in
            guard window.isActive != false else { return nil }
            return window.sourceIdentifier?.lowercased()
        })
        appendLegacyModelWindow(
            root: root,
            key: "seven_day_sonnet",
            title: "Sonnet only",
            modelToken: "sonnet",
            scopedIdentities: scopedIdentities,
            windows: &weeklyWindows,
            consumedKeys: &consumedKeys
        )
        appendLegacyModelWindow(
            root: root,
            key: "seven_day_opus",
            title: "Opus only",
            modelToken: "opus",
            scopedIdentities: scopedIdentities,
            windows: &weeklyWindows,
            consumedKeys: &consumedKeys
        )

        appendFeatureWindow(
            root: root,
            keys: ["seven_day_omelette"],
            id: "claude-design",
            title: "Claude Design",
            windows: &featureWindows,
            consumedKeys: &consumedKeys
        )
        appendFeatureWindow(
            root: root,
            keys: ["seven_day_cowork", "cowork"],
            id: "claude-cowork",
            title: "Cowork",
            windows: &featureWindows,
            consumedKeys: &consumedKeys
        )
        appendFeatureWindow(
            root: root,
            keys: ["seven_day_oauth_apps"],
            id: "claude-oauth-apps",
            title: "OAuth apps",
            windows: &featureWindows,
            consumedKeys: &consumedKeys
        )
        appendFeatureWindow(
            root: root,
            keys: [
                "seven_day_routines",
                "seven_day_claude_routines",
                "claude_routines",
                "routines",
                "routine",
            ],
            id: "claude-routines",
            title: "Daily Routines",
            windows: &featureWindows,
            consumedKeys: &consumedKeys
        )

        consumedKeys.insert("extra_usage")
        for key in root.keys.sorted() where !consumedKeys.contains(key) {
            guard let unknownBucket = bucket(root[key]) else { continue }
            featureWindows.append(makeWindow(
                unknownBucket,
                id: "claude-unknown-\(slug(key))",
                title: readableName(key),
                duration: inferredDuration(for: key),
                sourceIdentifier: key
            ))
        }

        var sections: [UsageSection] = []
        if !sessionWindows.isEmpty {
            sections.append(UsageSection(
                id: "claude-session-limits",
                title: "Plan usage limits",
                windows: deduplicated(sessionWindows)
            ))
        }
        if !weeklyWindows.isEmpty {
            sections.append(UsageSection(
                id: "claude-weekly-limits",
                title: "Weekly limits",
                windows: deduplicated(weeklyWindows)
            ))
        }
        if !featureWindows.isEmpty {
            sections.append(UsageSection(
                id: "claude-feature-limits",
                title: "Additional limits",
                windows: deduplicated(featureWindows)
            ))
        }

        var detailSections: [UsageDetailSection] = []
        if let routineUsed = auxiliary.routineUsed, let routineLimit = auxiliary.routineLimit {
            detailSections.append(UsageDetailSection(
                id: "claude-additional-features",
                title: "Additional features",
                items: [UsageDetailItem(
                    id: "claude-routine-budget",
                    title: "Daily included routine runs",
                    value: "\(routineUsed) / \(routineLimit)"
                )]
            ))
        }

        let extraUsage = root["extra_usage"] as? [String: Any]
        let extraItems = extraUsageItems(extraUsage, auxiliary: auxiliary)
        if !extraItems.isEmpty {
            detailSections.append(UsageDetailSection(
                id: "claude-extra-usage",
                title: "Extra usage",
                items: extraItems
            ))
        }

        return ProviderUsageSnapshot(
            provider: .anthropic,
            account: nonEmpty(account),
            plan: nonEmpty(plan),
            sections: sections,
            detailSections: detailSections,
            notices: [],
            updatedAt: now
        )
    }

    static func auxiliaryUsage(
        creditsData: Data?,
        bundlesData: Data?,
        routineData: Data?
    ) -> ClaudeAuxiliaryUsage {
        var result = ClaudeAuxiliaryUsage.empty
        if let creditsData,
           let root = try? JSONSerialization.jsonObject(with: creditsData) as? [String: Any] {
            result.prepaidAmount = flexibleDouble(root["amount"])
            result.prepaidCurrency = root["currency"] as? String
            if root.keys.contains("auto_reload_settings") {
                result.autoReloadEnabled = !(root["auto_reload_settings"] is NSNull)
            }
            result.pendingInvoiceAmount = flexibleDouble(root["pending_invoice_amount_cents"])
        }
        if let bundlesData,
           let root = try? JSONSerialization.jsonObject(with: bundlesData) as? [String: Any] {
            result.purchasesResetAt = flexibleDate(root["purchases_reset_at"])
            result.bundlePaidThisMonth = flexibleDouble(root["bundle_paid_this_month_minor_units"])
            result.bundleMonthlyCap = flexibleDouble(root["bundle_monthly_cap_minor_units"])
            result.bundleCurrency = root["currency"] as? String
        }
        if let routineData,
           let root = try? JSONSerialization.jsonObject(with: routineData) as? [String: Any] {
            result.routineUsed = flexibleDouble(root["used"]).map { Int($0) }
            result.routineLimit = flexibleDouble(root["limit"]).map { Int($0) }
        }
        return result
    }

    static func planDisplayName(subscriptionType: String?, rateLimitTier: String?) -> String? {
        let subscription = normalizedWords(subscriptionType)
        let tier = normalizedWords(rateLimitTier)
        let words = subscription + tier

        let base: String?
        if words.contains("max") {
            base = "Claude Max"
        } else if words.contains("pro") {
            base = "Claude Pro"
        } else if words.contains("team") {
            base = "Claude Team"
        } else if words.contains("enterprise") {
            base = "Claude Enterprise"
        } else if words.contains("ultra") {
            base = "Claude Ultra"
        } else {
            base = nonEmpty(subscriptionType).map { "Claude \(readableName($0))" }
                ?? nonEmpty(rateLimitTier).map { "Claude \(readableTier($0))" }
        }

        guard let base else { return nil }
        if base == "Claude Max",
           let multiplier = tier.first(where: { word in
               word.hasSuffix("x") && Int(word.dropLast()) != nil
           }) {
            return "\(base) \(multiplier)"
        }
        return base
    }

    private static func scopedLimits(from value: Any?) -> (weekly: [UsageWindow], other: [UsageWindow]) {
        guard let limits = value as? [Any] else { return ([], []) }
        var weekly: [UsageWindow] = []
        var other: [UsageWindow] = []
        var seen = Set<String>()

        for (index, rawEntry) in limits.enumerated() {
            guard let entry = rawEntry as? [String: Any],
                  let percent = flexibleDouble(entry["percent"]),
                  percent.isFinite
            else {
                continue
            }
            let kind = nonEmpty(entry["kind"] as? String)?.lowercased()
            let group = nonEmpty(entry["group"] as? String)?.lowercased()
            let scope = entry["scope"] as? [String: Any]
            let model = scope?["model"] as? [String: Any]
            let modelID = nonEmpty(model?["id"] as? String)
            let modelName = nonEmpty(model?["display_name"] as? String)
            let modelTitle = modelName ?? modelID.map(readableName)
            let isAllModels = isAllModelsScope(modelID: modelID, modelName: modelName)
            let identityParts = [kind, group, modelID ?? modelName].compactMap { $0 }
            let identity = identityParts.isEmpty ? "limit-\(index)" : identityParts.joined(separator: "-")
            let generatedID = "claude-limit-\(slug(identity))"
            let isWeeklyScoped = kind == "weekly_scoped" && group == "weekly"
            let id = isWeeklyScoped && isAllModels ? "claude-weekly-all-models" : generatedID
            guard seen.insert(id).inserted else { continue }

            let sourceIdentifier = [modelID, modelName, kind, group]
                .compactMap { $0 }
                .joined(separator: " ")
            let isActive = flexibleBool(entry["is_active"])

            if isWeeklyScoped {
                let title: String
                if isAllModels {
                    title = "All models"
                } else {
                    let name = modelTitle ?? "Scoped weekly limit"
                    title = name.lowercased().hasSuffix(" only") ? name : "\(name) only"
                }
                weekly.append(UsageWindow(
                    id: id,
                    title: title,
                    usedPercent: percent,
                    displayMode: .used,
                    resetsAt: flexibleDate(entry["resets_at"]),
                    duration: 7 * 24 * 60 * 60,
                    sourceIdentifier: sourceIdentifier,
                    isActive: isActive
                ))
            } else {
                other.append(UsageWindow(
                    id: id,
                    title: modelTitle ?? scopedLimitTitle(kind: kind, group: group),
                    usedPercent: percent,
                    displayMode: .used,
                    resetsAt: flexibleDate(entry["resets_at"]),
                    duration: duration(forGroup: group),
                    sourceIdentifier: sourceIdentifier.isEmpty ? identity : sourceIdentifier,
                    isActive: isActive
                ))
            }
        }
        return (weekly, other)
    }

    private static func scopedLimitTitle(kind: String?, group: String?) -> String {
        switch slug(kind ?? "") {
        case "routine", "routines", "claude-routines":
            return "Daily Routines"
        case "oauth-apps":
            return "OAuth apps"
        case "cowork":
            return "Cowork"
        default:
            return readableName(kind ?? group ?? "Additional limit")
        }
    }

    private static func duration(forGroup group: String?) -> TimeInterval? {
        switch group {
        case "hourly": return 60 * 60
        case "daily": return 24 * 60 * 60
        case "weekly": return 7 * 24 * 60 * 60
        case "monthly": return 30 * 24 * 60 * 60
        default: return nil
        }
    }

    private static func appendLegacyModelWindow(
        root: [String: Any],
        key: String,
        title: String,
        modelToken: String,
        scopedIdentities: Set<String>,
        windows: inout [UsageWindow],
        consumedKeys: inout Set<String>
    ) {
        consumedKeys.insert(key)
        let hasScopedReplacement = scopedIdentities.contains { $0.contains(modelToken) }
        guard !hasScopedReplacement, let bucket = bucket(root[key]) else { return }
        windows.append(makeWindow(
            bucket,
            id: "claude-weekly-\(modelToken)",
            title: title,
            duration: 7 * 24 * 60 * 60,
            sourceIdentifier: key
        ))
    }

    private static func appendFeatureWindow(
        root: [String: Any],
        keys: [String],
        id: String,
        title: String,
        windows: inout [UsageWindow],
        consumedKeys: inout Set<String>
    ) {
        keys.forEach { consumedKeys.insert($0) }
        for key in keys {
            guard let bucket = bucket(root[key]) else { continue }
            windows.append(makeWindow(
                bucket,
                id: id,
                title: title,
                duration: 7 * 24 * 60 * 60,
                sourceIdentifier: key
            ))
            return
        }
    }

    private static func makeWindow(
        _ bucket: Bucket,
        id: String,
        title: String,
        duration: TimeInterval?,
        sourceIdentifier: String
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            title: title,
            usedPercent: bucket.utilization,
            displayMode: .used,
            resetsAt: bucket.resetsAt,
            duration: duration,
            sourceIdentifier: sourceIdentifier
        )
    }

    private static func bucket(_ value: Any?) -> Bucket? {
        guard let dictionary = value as? [String: Any],
              let utilization = flexibleDouble(dictionary["utilization"] ?? dictionary["percent"]),
              utilization.isFinite
        else {
            return nil
        }
        return Bucket(
            utilization: utilization,
            resetsAt: flexibleDate(dictionary["resets_at"] ?? dictionary["reset_at"])
        )
    }

    private static func extraUsageItems(
        _ extra: [String: Any]?,
        auxiliary: ClaudeAuxiliaryUsage
    ) -> [UsageDetailItem] {
        var items: [UsageDetailItem] = []
        let currency = nonEmpty(extra?["currency"] as? String)
            ?? nonEmpty(auxiliary.prepaidCurrency)
            ?? nonEmpty(auxiliary.bundleCurrency)
            ?? "USD"

        if let enabled = flexibleBool(extra?["is_enabled"]) {
            items.append(UsageDetailItem(
                id: "claude-extra-enabled",
                title: "Status",
                value: enabled ? "On" : "Off"
            ))
        }
        // Always surface spend when the extra-usage block exists, defaulting to zero
        // when the feature is off, so the dashboard consistently shows a Spent row.
        if extra?["is_enabled"] != nil || extra?["used_credits"] != nil {
            let spent = flexibleDouble(extra?["used_credits"]) ?? 0
            items.append(UsageDetailItem(
                id: "claude-extra-spent",
                title: "Spent",
                value: formatMoney(spent, currency: currency)
            ))
        }
        if let limit = flexibleDouble(extra?["monthly_limit"]) {
            items.append(UsageDetailItem(
                id: "claude-extra-monthly-limit",
                title: "Monthly limit",
                value: formatMoney(limit, currency: currency)
            ))
        } else if flexibleBool(extra?["is_enabled"]) == true {
            items.append(UsageDetailItem(
                id: "claude-extra-monthly-limit",
                title: "Monthly limit",
                value: "Unlimited"
            ))
        }
        if let amount = auxiliary.prepaidAmount {
            items.append(UsageDetailItem(
                id: "claude-prepaid-balance",
                title: "Balance",
                value: formatMoney(amount, currency: auxiliary.prepaidCurrency ?? currency)
            ))
        }
        if let enabled = auxiliary.autoReloadEnabled {
            items.append(UsageDetailItem(
                id: "claude-auto-reload",
                title: "Auto-reload",
                value: enabled ? "On" : "Off"
            ))
        }
        if let pending = auxiliary.pendingInvoiceAmount, pending > 0 {
            items.append(UsageDetailItem(
                id: "claude-pending-invoice",
                title: "Pending invoice",
                value: formatMoney(pending, currency: auxiliary.prepaidCurrency ?? currency)
            ))
        }
        if let paid = auxiliary.bundlePaidThisMonth {
            items.append(UsageDetailItem(
                id: "claude-bundle-paid",
                title: "Purchased this month",
                value: formatMoney(paid, currency: auxiliary.bundleCurrency ?? currency),
                detail: auxiliary.bundleMonthlyCap.map {
                    "Monthly cap \(formatMoney($0, currency: auxiliary.bundleCurrency ?? currency))"
                }
            ))
        }
        if let reset = auxiliary.purchasesResetAt {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.dateFormat = "MMM d"
            items.append(UsageDetailItem(
                id: "claude-purchases-reset",
                title: "Purchase limit resets",
                value: formatter.string(from: reset)
            ))
        }
        return items
    }

    private static func formatMoney(_ minorUnits: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: minorUnits / 100))
            ?? String(format: "$%.2f", minorUnits / 100)
    }

    private static func inferredDuration(for key: String) -> TimeInterval? {
        if key.contains("five_hour") { return 5 * 60 * 60 }
        if key.contains("seven_day") || key.contains("weekly") { return 7 * 24 * 60 * 60 }
        return nil
    }

    private static func isAllModelsScope(modelID: String?, modelName: String?) -> Bool {
        let nameSlug = modelName.map(slug) ?? ""
        let idSlug = modelID.map(slug) ?? ""
        return nameSlug == "all-models" || idSlug == "all-models" || idSlug.hasSuffix("-all-models")
    }

    private static func deduplicated(_ windows: [UsageWindow]) -> [UsageWindow] {
        var seen = Set<String>()
        return windows.filter { seen.insert($0.id).inserted }
    }

    private static func flexibleDouble(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string.replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func flexibleBool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.intValue != 0
        case let string as String:
            switch string.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func flexibleDate(_ value: Any?) -> Date? {
        if let number = flexibleDouble(value), number > 0 {
            return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
        }
        guard let string = value as? String else { return nil }
        return ISO8601.date(from: string)
    }

    private static func normalizedWords(_ value: String?) -> [String] {
        value?.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init) ?? []
    }

    private static func readableTier(_ raw: String) -> String {
        var value = raw
        for prefix in ["default_claude_", "default_"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }
        return readableName(value)
    }

    nonisolated private static func readableName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                if lower == "oauth" { return "OAuth" }
                if lower == "api" { return "API" }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    nonisolated private static func slug(_ value: String) -> String {
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
}

enum ClaudeUsageService {
    private static let oauthUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let oauthRefreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    struct Result: Sendable {
        let snapshot: ProviderUsageSnapshot
        let credentials: ClaudeCredentials
    }

    static func fetch(credentials originalCredentials: ClaudeCredentials) async throws -> Result {
        guard originalCredentials.isComplete else {
            throw UsageServiceError.notConfigured(.anthropic)
        }

        var credentials = originalCredentials
        var usageData: Data?
        var usedOAuth = false
        var oauthFailure: Error?

        if credentials.hasOAuthCredentials {
            do {
                if credentials.shouldRefreshOAuth {
                    credentials = try await refreshOAuth(credentials)
                }
                usageData = try await fetchOAuthUsage(credentials)
                usedOAuth = true
            } catch ClaudeOAuthRequestError.unauthorized {
                do {
                    credentials = try await refreshOAuth(credentials)
                    usageData = try await fetchOAuthUsage(credentials)
                    usedOAuth = true
                } catch {
                    oauthFailure = error
                }
            } catch {
                oauthFailure = error
            }
        }

        if usageData == nil, credentials.hasWebCredentials {
            usageData = try await fetchWebUsage(credentials)
            usedOAuth = false
        }

        guard let usageData else {
            if let oauthFailure {
                throw mapOAuthError(oauthFailure)
            }
            throw UsageServiceError.invalidCredentials(.anthropic)
        }

        var accountInfo: ClaudeAccountInfo?
        var auxiliary = ClaudeAuxiliaryUsage.empty
        var boostNotices: [UsageNotice] = []
        if credentials.hasWebCredentials {
            let webCredentials = credentials
            async let account = fetchOrganizationInfo(webCredentials)
            async let extras = fetchAuxiliaryUsage(webCredentials)
            async let boosts = fetchBoostNotices(webCredentials)
            accountInfo = await account
            auxiliary = await extras
            boostNotices = await boosts
        }

        let oauthPlan = ClaudeUsageNormalizer.planDisplayName(
            subscriptionType: credentials.oauthSubscriptionType,
            rateLimitTier: credentials.oauthRateLimitTier
        )
        var snapshot = try ClaudeUsageNormalizer.snapshot(
            from: usageData,
            account: accountInfo?.email,
            plan: oauthPlan ?? accountInfo?.plan,
            auxiliary: auxiliary
        )

        var addedNotices = boostNotices
        if !usedOAuth, credentials.hasOAuthCredentials, oauthFailure != nil {
            addedNotices.append(UsageNotice(
                id: "claude-oauth-fallback",
                kind: .information,
                message: "Using the saved browser session because Claude OAuth was unavailable."
            ))
        }
        if !addedNotices.isEmpty {
            snapshot = ProviderUsageSnapshot(
                provider: snapshot.provider,
                account: snapshot.account,
                plan: snapshot.plan,
                sections: snapshot.sections,
                detailSections: snapshot.detailSections,
                notices: addedNotices + snapshot.notices,
                updatedAt: snapshot.updatedAt
            )
        }
        return Result(snapshot: snapshot, credentials: credentials)
    }

    private static func fetchOAuthUsage(_ credentials: ClaudeCredentials) async throws -> Data {
        guard let token = credentials.oauthAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            throw ClaudeOAuthRequestError.unauthorized
        }

        var request = URLRequest(
            url: oauthUsageURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ClaudeOAuthRequestError.invalidResponse
        }
        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            throw ClaudeOAuthRequestError.unauthorized
        case 403:
            throw ClaudeOAuthRequestError.forbidden
        case 429:
            throw ClaudeOAuthRequestError.rateLimited(retryAfterDate(from: response))
        default:
            throw ClaudeOAuthRequestError.status(response.statusCode)
        }
    }

    private static func fetchWebUsage(_ credentials: ClaudeCredentials) async throws -> Data {
        guard let organizationID = normalizedOrganizationID(credentials.organizationID) else {
            throw UsageServiceError.message("The Claude organization ID must be a valid UUID.")
        }
        let url = organizationURL(organizationID, path: ["usage"])
        let request = authenticatedWebRequest(url: url, sessionKey: credentials.sessionKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UsageServiceError.invalidResponse(.anthropic)
        }
        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            throw UsageServiceError.invalidCredentials(.anthropic)
        case 403:
            let body = String(data: data.prefix(2_000), encoding: .utf8)?.lowercased() ?? ""
            let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if contentType.contains("text/html") || body.contains("cloudflare") || body.contains("challenge") {
                throw UsageServiceError.claudeWebChallenge
            }
            throw UsageServiceError.invalidCredentials(.anthropic)
        case 429:
            throw UsageServiceError.rateLimited(.anthropic, retryAfterDate(from: response))
        default:
            throw UsageServiceError.server(.anthropic, response.statusCode)
        }
    }

    private static func refreshOAuth(_ credentials: ClaudeCredentials) async throws -> ClaudeCredentials {
        guard let refreshToken = credentials.oauthRefreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !refreshToken.isEmpty
        else {
            throw ClaudeOAuthRequestError.unauthorized
        }

        var request = URLRequest(
            url: oauthRefreshURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: oauthClientID),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ClaudeOAuthRequestError.invalidResponse
        }
        guard response.statusCode == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = payload["access_token"] as? String,
              !accessToken.isEmpty
        else {
            if [400, 401, 403].contains(response.statusCode) {
                throw ClaudeOAuthRequestError.unauthorized
            }
            if response.statusCode == 429 {
                throw ClaudeOAuthRequestError.rateLimited(retryAfterDate(from: response))
            }
            throw ClaudeOAuthRequestError.status(response.statusCode)
        }

        var updated = credentials
        updated.oauthAccessToken = accessToken
        updated.oauthRefreshToken = (payload["refresh_token"] as? String) ?? refreshToken
        let expiresIn = flexibleDouble(payload["expires_in"]) ?? 3600
        updated.oauthExpiresAt = Date().addingTimeInterval(expiresIn)
        return updated
    }

    private static func mapOAuthError(_ error: Error) -> Error {
        switch error {
        case ClaudeOAuthRequestError.unauthorized:
            return UsageServiceError.invalidCredentials(.anthropic)
        case ClaudeOAuthRequestError.forbidden:
            return UsageServiceError.claudeOAuthScope
        case ClaudeOAuthRequestError.rateLimited(let retryAfter):
            return UsageServiceError.rateLimited(.anthropic, retryAfter)
        case ClaudeOAuthRequestError.invalidResponse:
            return UsageServiceError.invalidResponse(.anthropic)
        case ClaudeOAuthRequestError.status(let status):
            return UsageServiceError.server(.anthropic, status)
        default:
            return error
        }
    }

    private static func authenticatedWebRequest(url: URL, sessionKey: String) -> URLRequest {
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

    private static func fetchOrganizationInfo(_ credentials: ClaudeCredentials) async -> ClaudeAccountInfo? {
        guard let organizationID = normalizedOrganizationID(credentials.organizationID) else { return nil }
        let url = organizationURL(organizationID)
        guard let data = await optionalWebData(url: url, credentials: credentials),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let directEmail = root["email"] as? String
        let name = root["name"] as? String
        let derivedEmail: String?
        if let name, let range = name.range(of: "'s Organization") {
            derivedEmail = String(name[..<range.lowerBound])
        } else {
            derivedEmail = name
        }
        let plan = ClaudeUsageNormalizer.planDisplayName(
            subscriptionType: root["subscription_type"] as? String,
            rateLimitTier: root["rate_limit_tier"] as? String
        )
        return ClaudeAccountInfo(email: directEmail ?? derivedEmail, plan: plan)
    }

    private static func fetchAuxiliaryUsage(_ credentials: ClaudeCredentials) async -> ClaudeAuxiliaryUsage {
        guard let organizationID = normalizedOrganizationID(credentials.organizationID) else { return .empty }

        let creditsURL = organizationURL(organizationID, path: ["prepaid", "credits"])
        let bundlesURL = organizationURL(organizationID, path: ["prepaid", "bundles"])
        let routineURL = URL(string: "https://claude.ai/v1/code/routines/run-budget")!

        async let creditsData = optionalWebData(url: creditsURL, credentials: credentials)
        async let bundlesData = optionalWebData(url: bundlesURL, credentials: credentials)
        async let routineData = optionalRoutineData(url: routineURL, credentials: credentials)
        let (credits, bundles, routine) = await (creditsData, bundlesData, routineData)

        return ClaudeUsageNormalizer.auxiliaryUsage(
            creditsData: credits,
            bundlesData: bundles,
            routineData: routine
        )
    }

    /// Fetches claude.ai's org bootstrap payload and extracts any active
    /// usage-limit promotion/boost banner. The banner is delivered as a
    /// GrowthBook feature whose value is a locale → Markdown map; we surface
    /// the English string when it looks like a usage banner (Markdown link +
    /// a limit/boost keyword), so new promotions appear automatically without
    /// hardcoding a feature id.
    private static func fetchBoostNotices(_ credentials: ClaudeCredentials) async -> [UsageNotice] {
        guard let organizationID = normalizedOrganizationID(credentials.organizationID),
              var components = URLComponents(
                  string: "https://claude.ai/edge-api/bootstrap/\(organizationID)/app_start"
              )
        else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "statsig_hashing_algorithm", value: "djb2"),
            URLQueryItem(name: "growthbook_format", value: "sdk"),
            URLQueryItem(name: "include_system_prompts", value: "false"),
        ]
        guard let url = components.url,
              let data = await optionalWebData(url: url, credentials: credentials),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }
        return boostNotices(from: root)
    }

    private static func boostNotices(from root: [String: Any]) -> [UsageNotice] {
        guard let growthbook = root["org_growthbook"] as? [String: Any],
              let features = growthbook["features"] as? [String: Any]
        else {
            return []
        }

        var notices: [UsageNotice] = []
        var seen = Set<String>()
        for (featureID, raw) in features {
            guard let feature = raw as? [String: Any] else { continue }

            // Prefer a forced rule value (what this org actually gets); fall
            // back to the default value.
            var localized = feature["defaultValue"] as? [String: Any]
            if let rules = feature["rules"] as? [[String: Any]] {
                for rule in rules {
                    if let forced = rule["force"] as? [String: Any] {
                        localized = forced
                        break
                    }
                }
            }

            guard let localized,
                  let message = (localized["en-US"] as? String) ?? (localized["en"] as? String),
                  looksLikeUsageBanner(message)
            else { continue }

            let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { continue }
            notices.append(UsageNotice(id: "claude-boost-\(featureID)", kind: .information, message: cleaned))
        }
        return notices
    }

    private static func looksLikeUsageBanner(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasLink = lower.contains("](http")
        let hasKeyword = ["limit", "boost", "promotion", "usage", "higher"].contains { lower.contains($0) }
        return hasLink && hasKeyword
    }

    private static func optionalWebData(url: URL, credentials: ClaudeCredentials) async -> Data? {
        let request = authenticatedWebRequest(url: url, sessionKey: credentials.sessionKey)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200
        else {
            return nil
        }
        return data
    }

    private static func optionalRoutineData(url: URL, credentials: ClaudeCredentials) async -> Data? {
        var request = authenticatedWebRequest(url: url, sessionKey: credentials.sessionKey)
        request.setValue(credentials.organizationID, forHTTPHeaderField: "x-organization-uuid")
        request.setValue("ccr-triggers-2026-01-30", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200
        else {
            return nil
        }
        return data
    }

    private static func normalizedOrganizationID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else { return nil }
        return trimmed
    }

    private static func organizationURL(_ organizationID: String, path: [String] = []) -> URL {
        var url = URL(string: "https://claude.ai/api/organizations")!
        url.appendPathComponent(organizationID)
        path.forEach { url.appendPathComponent($0) }
        return url
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

    private static func flexibleDouble(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func flexibleDate(_ value: Any?) -> Date? {
        if let number = flexibleDouble(value), number > 0 {
            return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
        }
        guard let string = value as? String else { return nil }
        return ISO8601.date(from: string)
    }
}
