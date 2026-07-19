import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case anthropic
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic:
            return "Claude"
        case .openAI:
            return "OpenAI"
        }
    }

    var companyName: String {
        switch self {
        case .anthropic:
            return "Anthropic"
        case .openAI:
            return "OpenAI"
        }
    }
}

enum UsageMetricDisplayMode: String, Codable, Sendable, Equatable {
    case used
    case remaining

    var label: String {
        switch self {
        case .used:
            return "used"
        case .remaining:
            return "remaining"
        }
    }
}

enum UsageQuotaState: Sendable, Equatable {
    case normal
    case warning
    case critical
    case exhausted
    case unavailable
    case inactive
}

struct UsageWindow: Identifiable, Sendable {
    let id: String
    let title: String
    /// Canonical provider utilization. All provider payloads are normalized to percent used.
    let usedPercent: Double
    let displayMode: UsageMetricDisplayMode
    let resetsAt: Date?
    let duration: TimeInterval?
    let sourceIdentifier: String?
    let detail: String?
    let isAllowed: Bool?
    let isLimitReached: Bool?
    let isActive: Bool?

    init(
        id: String,
        title: String,
        usedPercent: Double,
        displayMode: UsageMetricDisplayMode,
        resetsAt: Date?,
        duration: TimeInterval?,
        sourceIdentifier: String? = nil,
        detail: String? = nil,
        isAllowed: Bool? = nil,
        isLimitReached: Bool? = nil,
        isActive: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.displayMode = displayMode
        self.resetsAt = resetsAt
        self.duration = duration
        self.sourceIdentifier = sourceIdentifier
        self.detail = detail
        self.isAllowed = isAllowed
        self.isLimitReached = isLimitReached
        self.isActive = isActive
    }

    var clampedUsedPercent: Double {
        min(max(usedPercent.isFinite ? usedPercent : 0, 0), 100)
    }

    var remainingPercent: Double {
        100 - clampedUsedPercent
    }

    var displayPercent: Double {
        switch displayMode {
        case .used:
            return clampedUsedPercent
        case .remaining:
            return remainingPercent
        }
    }

    /// The usage bar always visualizes quota consumed, regardless of whether the provider labels
    /// the number as used or remaining. A limit with 10% remaining is therefore 90% full.
    var barFraction: Double {
        clampedUsedPercent / 100
    }

    /// Progress through the quota period, derived from its known duration and next reset.
    /// A weekly limit that resets in 10.5 hours is roughly 94% through its current window.
    func windowElapsedFraction(at date: Date) -> Double? {
        guard let resetsAt,
              let duration,
              duration.isFinite,
              duration > 0
        else {
            return nil
        }

        let elapsed = duration - resetsAt.timeIntervalSince(date)
        guard elapsed.isFinite else { return nil }
        return min(max(elapsed / duration, 0), 1)
    }

    func windowElapsedPercentageDescription(at date: Date) -> String? {
        windowElapsedFraction(at: date).map { Self.formattedPercent($0 * 100) }
    }

    var percentageDescription: String {
        "\(Self.formattedPercent(displayPercent)) \(displayMode.label)"
    }

    var accessibilityDescription: String {
        "\(Self.formattedPercent(clampedUsedPercent)) used, \(Self.formattedPercent(remainingPercent)) remaining"
    }

    var quotaState: UsageQuotaState {
        if isActive == false { return .inactive }
        if isLimitReached == true || clampedUsedPercent >= 100 { return .exhausted }
        if isAllowed == false { return .unavailable }
        if clampedUsedPercent >= 90 { return .critical }
        if clampedUsedPercent >= 75 { return .warning }
        return .normal
    }

    var statusDescription: String? {
        switch quotaState {
        case .inactive:
            return "Inactive"
        case .unavailable:
            return "Currently unavailable"
        case .exhausted:
            return "Limit reached"
        case .normal, .warning, .critical:
            return nil
        }
    }

    private static func formattedPercent(_ value: Double) -> String {
        let clamped = min(max(value.isFinite ? value : 0, 0), 100)
        if clamped > 0, clamped < 1 { return "<1%" }
        if clamped > 99, clamped < 100 { return ">99%" }
        return "\(Int(clamped.rounded()))%"
    }
}

struct UsageSection: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let windows: [UsageWindow]

    init(id: String, title: String, subtitle: String? = nil, windows: [UsageWindow]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.windows = windows
    }
}

struct UsageDetailItem: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
    let detail: String?

    init(id: String, title: String, value: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.value = value
        self.detail = detail
    }
}

struct UsageDetailSection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [UsageDetailItem]
    /// Optional trailing note rendered beneath the items. Supports Markdown
    /// links (e.g. "… [Learn more](https://…)").
    let footnote: String?

    init(id: String, title: String, items: [UsageDetailItem], footnote: String? = nil) {
        self.id = id
        self.title = title
        self.items = items
        self.footnote = footnote
    }
}

struct UsageNotice: Identifiable, Sendable {
    enum Kind: String, Sendable, Equatable {
        case information
        case warning
        case error
    }

    let id: String
    let kind: Kind
    let message: String
}

struct ProviderUsageSnapshot: Sendable {
    let provider: AIProvider
    let account: String?
    let plan: String?
    let sections: [UsageSection]
    let detailSections: [UsageDetailSection]
    let notices: [UsageNotice]
    let updatedAt: Date

    var subtitle: String? {
        let values = [account, plan].compactMap { value -> String? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return value
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    var windows: [UsageWindow] {
        sections.flatMap(\.windows)
    }
}

enum UsageServiceError: LocalizedError, Sendable {
    case notConfigured(AIProvider)
    case invalidCredentials(AIProvider)
    case invalidResponse(AIProvider)
    case server(AIProvider, Int)
    case rateLimited(AIProvider, Date?)
    case claudeWebChallenge
    case claudeOAuthScope
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .notConfigured(provider):
            return "Configure \(provider.displayName) in Settings to view usage."
        case let .invalidCredentials(provider):
            return "\(provider.displayName) rejected the saved credentials. Update them in Settings."
        case let .invalidResponse(provider):
            return "Volt could not read the usage response returned by \(provider.displayName)."
        case let .server(provider, status):
            return "\(provider.displayName) returned HTTP \(status). Try again in a moment."
        case let .rateLimited(provider, retryAfter):
            if let retryAfter, retryAfter > Date() {
                return "\(provider.displayName) is temporarily rate-limiting usage checks. Try again \(retryAfter.formatted(.relative(presentation: .named)))."
            }
            return "\(provider.displayName) is temporarily rate-limiting usage checks. Wait a few minutes, then refresh."
        case .claudeWebChallenge:
            return "Claude blocked the browser-session request. Import Claude Code credentials in Settings, or update the saved session key."
        case .claudeOAuthScope:
            return "The Claude OAuth token cannot read account usage. Run `claude login`, then import ~/.claude/.credentials.json again."
        case let .message(message):
            return message
        }
    }
}
