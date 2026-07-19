import XCTest
@testable import Volt

final class ProviderUsagePresentationTests: XCTestCase {
    func testOpenAIDashboardShowsOnlyWeeklyUsedQuotaAndResetList() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fiveHourReset = now.addingTimeInterval(900)
        let weeklyReset = now.addingTimeInterval(86_400)
        let raw = ProviderUsageSnapshot(
            provider: .openAI,
            account: "fixture@example.invalid",
            plan: "Pro 5x",
            sections: [
                UsageSection(
                    id: "openai-plan-limits",
                    title: "Plan usage limits",
                    windows: [
                        UsageWindow(
                            id: "openai-plan-5-hour",
                            title: "5-hour limit",
                            usedPercent: 25,
                            displayMode: .remaining,
                            resetsAt: fiveHourReset,
                            duration: 5 * 60 * 60
                        ),
                        UsageWindow(
                            id: "openai-plan-weekly",
                            title: "Weekly limit",
                            usedPercent: 43,
                            displayMode: .remaining,
                            resetsAt: weeklyReset,
                            duration: 7 * 24 * 60 * 60
                        ),
                    ]
                ),
                UsageSection(
                    id: "openai-model-limits",
                    title: "Model & feature limits",
                    windows: [UsageWindow(
                        id: "openai-spark",
                        title: "Spark · Weekly",
                        usedPercent: 100,
                        displayMode: .remaining,
                        resetsAt: weeklyReset,
                        duration: 7 * 24 * 60 * 60
                    )]
                ),
            ],
            detailSections: [UsageDetailSection(
                id: "openai-credits",
                title: "Credits",
                items: [UsageDetailItem(id: "credit", title: "Credits", value: "Available")]
            )],
            notices: [
                UsageNotice(id: "openai-plan-limit-reached", kind: .warning, message: "Plan limit reached"),
                UsageNotice(id: "openai-spend-limit-reached", kind: .warning, message: "Spend limit reached"),
            ],
            updatedAt: now
        )

        let dashboard = raw.curatedForDashboard()

        XCTAssertEqual(dashboard.sections.map(\.title), ["Usage"])
        let weekly = try XCTUnwrap(dashboard.windows.first)
        XCTAssertEqual(dashboard.windows.count, 1)
        XCTAssertEqual(weekly.title, "Weekly usage limit")
        XCTAssertEqual(weekly.displayMode, .used)
        XCTAssertEqual(weekly.displayPercent, 43, accuracy: 0.001)
        XCTAssertEqual(weekly.barFraction, 0.43, accuracy: 0.001)

        let resets = try XCTUnwrap(dashboard.detailSections.first)
        XCTAssertEqual(resets.title, "Usage limit resets")
        XCTAssertEqual(resets.items.map(\.title), ["No usage limit resets available at this time"])
        XCTAssertEqual(resets.items.map(\.value), [""])
        XCTAssertEqual(dashboard.notices.map(\.id), ["openai-plan-limit-reached"])
        XCTAssertFalse(dashboard.sections.contains(where: { $0.title.contains("feature") }))
        XCTAssertFalse(dashboard.detailSections.contains(where: { $0.title == "Credits" }))
    }

    func testOpenAIDashboardSurfacesResetCreditsWhenPresent() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let raw = ProviderUsageSnapshot(
            provider: .openAI,
            account: "fixture@example.invalid",
            plan: "Pro 5x",
            sections: [
                UsageSection(
                    id: "openai-plan-limits",
                    title: "Plan usage limits",
                    windows: [UsageWindow(
                        id: "openai-plan-weekly",
                        title: "Weekly limit",
                        usedPercent: 20,
                        displayMode: .remaining,
                        resetsAt: now.addingTimeInterval(86_400),
                        duration: 7 * 24 * 60 * 60
                    )]
                ),
            ],
            detailSections: [UsageDetailSection(
                id: "openai-reset-credits",
                title: "Usage limit resets",
                items: [
                    UsageDetailItem(id: "openai-reset-credit-0", title: "5 credits", value: "Expires Jul 31, 2026"),
                    UsageDetailItem(id: "openai-reset-credit-1", title: "10 credits", value: "Expires Aug 7, 2026"),
                ]
            )],
            notices: [],
            updatedAt: now
        )

        let dashboard = raw.curatedForDashboard()

        let resets = try XCTUnwrap(dashboard.detailSections.first(where: { $0.title == "Usage limit resets" }))
        XCTAssertEqual(resets.items.map(\.title), ["5 credits", "10 credits"])
        XCTAssertEqual(resets.items.map(\.value), ["Expires Jul 31, 2026", "Expires Aug 7, 2026"])
        XCTAssertFalse(resets.items.contains(where: { $0.title == "No usage limit resets available at this time" }))
    }

    func testClaudeDashboardKeepsCurrentSessionAllModelsAndFableOnly() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let raw = ProviderUsageSnapshot(
            provider: .anthropic,
            account: nil,
            plan: "Claude Max 20x",
            sections: [
                UsageSection(
                    id: "claude-session-limits",
                    title: "Plan usage limits",
                    windows: [window(
                        id: "claude-session",
                        title: "Current session",
                        used: 34,
                        source: "five_hour",
                        duration: 5 * 60 * 60
                    )]
                ),
                UsageSection(
                    id: "claude-weekly-limits",
                    title: "Weekly limits",
                    windows: [
                        window(
                            id: "claude-weekly-all-models",
                            title: "All models",
                            used: 52,
                            source: "seven_day",
                            duration: 7 * 24 * 60 * 60
                        ),
                        window(
                            id: "claude-weekly-sonnet",
                            title: "Sonnet only",
                            used: 12,
                            source: "sonnet",
                            duration: 7 * 24 * 60 * 60
                        ),
                        window(
                            id: "claude-weekly-fable-source",
                            title: "Fable only",
                            used: 7,
                            source: "model fable weekly_scoped weekly",
                            duration: 7 * 24 * 60 * 60
                        ),
                    ]
                ),
                UsageSection(
                    id: "claude-feature-limits",
                    title: "Additional limits",
                    windows: [window(
                        id: "claude-cowork",
                        title: "Cowork",
                        used: 90,
                        source: "cowork",
                        duration: 7 * 24 * 60 * 60
                    )]
                ),
            ],
            detailSections: [UsageDetailSection(
                id: "claude-extra-usage",
                title: "Extra usage",
                items: [
                    UsageDetailItem(id: "claude-extra-enabled", title: "Status", value: "On"),
                    UsageDetailItem(id: "claude-extra-spent", title: "Spent", value: "$12.50"),
                    UsageDetailItem(id: "claude-extra-monthly-limit", title: "Monthly limit", value: "$100.00"),
                    UsageDetailItem(id: "claude-prepaid-balance", title: "Balance", value: "$37.50"),
                    UsageDetailItem(id: "claude-auto-reload", title: "Auto-reload", value: "On"),
                    UsageDetailItem(id: "claude-purchases-reset", title: "Purchase limit resets", value: "Aug 1"),
                ]
            )],
            notices: [],
            updatedAt: now
        )

        let dashboard = raw.curatedForDashboard()

        XCTAssertEqual(dashboard.sections.map(\.title), ["Current session", "Weekly limits"])
        XCTAssertEqual(dashboard.sections[0].windows.map(\.title), ["Current session"])
        XCTAssertEqual(dashboard.sections[1].windows.map(\.title), ["All models", "Fable"])
        XCTAssertFalse(dashboard.sections.contains(where: { $0.title == "Additional limits" }))
        XCTAssertFalse(dashboard.windows.contains(where: { $0.title.contains("Sonnet") || $0.title == "Cowork" }))

        XCTAssertEqual(dashboard.detailSections.map(\.title), ["Usage credits", "Spend limit"])
        XCTAssertEqual(dashboard.detailSections[0].items.map(\.title), ["Status", "Spent", "Resets"])
        XCTAssertEqual(dashboard.detailSections[0].items.map(\.value), ["On", "$12.50", "Aug 1"])
        XCTAssertEqual(dashboard.detailSections[1].items.map(\.title), ["Current balance", "Auto-reload"])
        XCTAssertEqual(dashboard.detailSections[1].items.map(\.value), ["$37.50", "On"])
    }

    func testClaudeOAuthOnlyDashboardGracefullyOmitsCreditSections() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let raw = ProviderUsageSnapshot(
            provider: .anthropic,
            account: nil,
            plan: "Claude Pro",
            sections: [UsageSection(
                id: "claude-session-limits",
                title: "Plan usage limits",
                windows: [window(
                    id: "claude-session",
                    title: "Current session",
                    used: 10,
                    source: "five_hour",
                    duration: 5 * 60 * 60
                )]
            )],
            detailSections: [],
            notices: [],
            updatedAt: now
        )

        let dashboard = raw.curatedForDashboard()

        XCTAssertEqual(dashboard.sections.map(\.title), ["Current session"])
        XCTAssertTrue(dashboard.detailSections.isEmpty)
    }

    private func window(
        id: String,
        title: String,
        used: Double,
        source: String,
        duration: TimeInterval
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            title: title,
            usedPercent: used,
            displayMode: .used,
            resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
            duration: duration,
            sourceIdentifier: source
        )
    }
}
