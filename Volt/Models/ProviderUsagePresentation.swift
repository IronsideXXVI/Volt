import Foundation

extension ProviderUsageSnapshot {
    /// Converts the defensively decoded provider response into Volt's intentional,
    /// provider-specific dashboard contract. Unknown API buckets remain decoded by the
    /// services, but they do not automatically become user-facing rows.
    func curatedForDashboard() -> ProviderUsageSnapshot {
        switch provider {
        case .openAI:
            return curatedOpenAI
        case .anthropic:
            return curatedClaude
        }
    }

    private var curatedOpenAI: ProviderUsageSnapshot {
        let planWindows = sections.first(where: { $0.id == "openai-plan-limits" })?.windows
            ?? windows.filter { $0.sourceIdentifier == "rate_limit" }

        let weekly = planWindows.first(where: { window in
            Self.isWeekly(window.duration) || window.title.localizedCaseInsensitiveContains("weekly")
        }).map { window in
            Self.copy(
                window,
                id: "openai-weekly-usage",
                title: "Weekly usage limit",
                displayMode: .used
            )
        }

        let usageSections: [UsageSection]
        if let weekly {
            usageSections = [UsageSection(
                id: "openai-usage",
                title: "Usage",
                subtitle: "Usage is shared across Codex, Work, Workspace Agents, and ChatGPT for Excel. It doesn’t include Chat conversations.",
                windows: [weekly]
            )]
        } else {
            usageSections = []
        }

        // Rather than the next reset time, surface any reset credits available to
        // use (parsed by the service from `rate_limit_reset_credits`) with their
        // expiry, or an explicit "none" message when there are none.
        let resetCreditItems = detailSections
            .first(where: { $0.id == "openai-reset-credits" })?.items ?? []
        let resetSectionItems = resetCreditItems.isEmpty
            ? [UsageDetailItem(
                id: "openai-no-reset-credits",
                title: "No usage limit resets available at this time.",
                value: ""
              )]
            : resetCreditItems
        let resetSections = [UsageDetailSection(
            id: "openai-usage-limit-resets",
            title: "Usage limit resets",
            items: resetSectionItems
        )]

        return ProviderUsageSnapshot(
            provider: provider,
            account: account,
            plan: plan,
            sections: usageSections,
            detailSections: resetSections,
            notices: notices.filter { $0.id == "openai-plan-limit-reached" },
            updatedAt: updatedAt
        )
    }

    private var curatedClaude: ProviderUsageSnapshot {
        let sourceWindows = windows
        let session = sourceWindows.first(where: { window in
            window.id == "claude-session" || window.sourceIdentifier == "five_hour"
        }).map { window in
            Self.copy(window, id: "claude-current-session", title: "Current session")
        }

        let allModels = sourceWindows.first(where: { window in
            window.id == "claude-weekly-all-models"
                || window.title.caseInsensitiveCompare("All models") == .orderedSame
        }).map { window in
            Self.copy(window, id: "claude-weekly-all-models", title: "All models")
        }

        let fable = sourceWindows.first(where: { window in
            window.title.localizedCaseInsensitiveContains("fable")
                || window.sourceIdentifier?.localizedCaseInsensitiveContains("fable") == true
        }).map { window in
            Self.copy(window, id: "claude-weekly-fable", title: "Fable")
        }

        var usageSections: [UsageSection] = []
        if let session {
            usageSections.append(UsageSection(
                id: "claude-current-session-section",
                title: "Current session",
                windows: [session]
            ))
        }

        let weekly = [allModels, fable].compactMap { $0 }
        if !weekly.isEmpty {
            usageSections.append(UsageSection(
                id: "claude-weekly-limits",
                title: "Weekly limits",
                windows: weekly
            ))
        }

        let rawDetails = detailSections.flatMap(\.items)
        let usageCreditItems = [
            Self.detailItem(
                in: rawDetails,
                id: "claude-extra-enabled",
                title: "Status"
            ),
            Self.detailItem(
                in: rawDetails,
                id: "claude-extra-spent",
                title: "Spent"
            ),
            Self.detailItem(
                in: rawDetails,
                id: "claude-purchases-reset",
                title: "Resets"
            ),
        ].compactMap { $0 }

        let spendLimitItems = [
            Self.detailItem(
                in: rawDetails,
                id: "claude-prepaid-balance",
                title: "Current balance"
            ),
            Self.detailItem(
                in: rawDetails,
                id: "claude-auto-reload",
                title: "Auto-reload"
            ),
        ].compactMap { $0 }

        var curatedDetails: [UsageDetailSection] = []
        if !usageCreditItems.isEmpty {
            curatedDetails.append(UsageDetailSection(
                id: "claude-usage-credits",
                title: "Usage credits",
                items: usageCreditItems,
                footnote: "Turn on usage credits to keep using Claude if you hit a limit. [Learn more](https://support.claude.com/en/articles/11647753-understanding-usage-and-length-limits)"
            ))
        }
        if !spendLimitItems.isEmpty {
            curatedDetails.append(UsageDetailSection(
                id: "claude-spend-limit",
                title: "Spend limit",
                items: spendLimitItems
            ))
        }

        return ProviderUsageSnapshot(
            provider: provider,
            account: account,
            plan: plan,
            sections: usageSections,
            detailSections: curatedDetails,
            notices: notices,
            updatedAt: updatedAt
        )
    }

    private static func copy(
        _ window: UsageWindow,
        id: String,
        title: String,
        displayMode: UsageMetricDisplayMode? = nil
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            title: title,
            usedPercent: window.usedPercent,
            displayMode: displayMode ?? window.displayMode,
            resetsAt: window.resetsAt,
            duration: window.duration,
            sourceIdentifier: window.sourceIdentifier,
            detail: window.detail,
            isAllowed: window.isAllowed,
            isLimitReached: window.isLimitReached,
            isActive: window.isActive
        )
    }

    private static func detailItem(
        in items: [UsageDetailItem],
        id: String,
        title: String
    ) -> UsageDetailItem? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        return UsageDetailItem(id: id, title: title, value: item.value, detail: item.detail)
    }

    private static func isWeekly(_ duration: TimeInterval?) -> Bool {
        guard let duration else { return false }
        return abs(duration - 7 * 24 * 60 * 60) < 60 * 60
    }
}
