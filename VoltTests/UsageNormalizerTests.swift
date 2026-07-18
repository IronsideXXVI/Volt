import XCTest
@testable import Volt

final class UsageNormalizerTests: XCTestCase {
    private let fixtureCredentials = OpenAICredentials(
        accessToken: "fixture-access-token",
        refreshToken: "",
        idToken: "",
        accountID: "",
        lastRefresh: nil
    )

    func testOpenAIWeeklyLimitDisplaysRemainingCapacity() throws {
        let snapshot = try OpenAIUsageNormalizer.snapshot(
            from: fixture("openai-weekly-only"),
            credentials: fixtureCredentials,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.title, "Weekly limit")
        XCTAssertEqual(window.usedPercent, 43, accuracy: 0.001)
        XCTAssertEqual(window.remainingPercent, 57, accuracy: 0.001)
        XCTAssertEqual(window.displayPercent, 57, accuracy: 0.001)
        XCTAssertEqual(window.barFraction, 0.57, accuracy: 0.001)
        XCTAssertEqual(window.displayMode, .remaining)
        XCTAssertEqual(snapshot.plan, "Pro 5x")
        XCTAssertEqual(try XCTUnwrap(window.resetsAt).timeIntervalSince1970, 1_784_500_000, accuracy: 0.001)
    }

    func testOpenAIPreservesSparkIdentityInsteadOfDuplicatingWeeklyTitle() throws {
        let snapshot = try OpenAIUsageNormalizer.snapshot(
            from: fixture("openai-main-and-spark"),
            credentials: fixtureCredentials
        )

        XCTAssertEqual(snapshot.sections.count, 2)
        XCTAssertEqual(snapshot.windows.map(\.title), ["Weekly limit", "GPT-5.3-Codex-Spark"])
        let spark = try XCTUnwrap(snapshot.windows.first(where: { $0.title == "GPT-5.3-Codex-Spark" }))
        XCTAssertEqual(spark.displayPercent, 100, accuracy: 0.001)
        XCTAssertEqual(spark.sourceIdentifier, "codex_bengalfox")
    }

    func testOpenAIMapsPrimarySecondaryAndRelativeReset() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try OpenAIUsageNormalizer.snapshot(
            from: fixture("openai-primary-secondary"),
            credentials: fixtureCredentials,
            now: now
        )

        XCTAssertEqual(snapshot.windows.map(\.title), ["5-hour limit", "Weekly limit"])
        XCTAssertEqual(snapshot.windows[0].displayPercent, 75, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.windows[0].resetsAt).timeIntervalSince(now), 900, accuracy: 0.001)
        XCTAssertNotNil(snapshot.windows[1].resetsAt)
        XCTAssertEqual(snapshot.plan, "Plus")
    }

    func testOpenAIDecodesCodeReviewSpendControlAndStatus() throws {
        let snapshot = try OpenAIUsageNormalizer.snapshot(
            from: fixture("openai-code-review"),
            credentials: fixtureCredentials
        )

        let codeReview = try XCTUnwrap(snapshot.sections.first(where: { $0.id == "openai-code-review-limits" }))
        XCTAssertEqual(codeReview.windows.first?.title, "Weekly limit")
        XCTAssertEqual(try XCTUnwrap(codeReview.windows.first).displayPercent, 88, accuracy: 0.001)

        let spend = try XCTUnwrap(snapshot.sections.first(where: { $0.id == "openai-spend-control" }))
        XCTAssertEqual(try XCTUnwrap(spend.windows.first).displayPercent, 75, accuracy: 0.001)
        XCTAssertTrue(snapshot.notices.contains(where: { $0.id == "openai-plan-limit-reached" }))
        XCTAssertTrue(snapshot.detailSections.contains(where: { $0.id == "openai-credits" }))
    }

    func testOpenAIPlanNamesMatchCodexProductLanguage() {
        XCTAssertEqual(OpenAIUsageNormalizer.planDisplayName("prolite"), "Pro 5x")
        XCTAssertEqual(OpenAIUsageNormalizer.planDisplayName("pro"), "Pro 20x")
        XCTAssertEqual(OpenAIUsageNormalizer.planDisplayName("free_workspace"), "Free workspace")
        XCTAssertEqual(OpenAIUsageNormalizer.planDisplayName("future_plan"), "Future Plan")
    }

    func testClaudeLegacyFieldsUsePercentUsedAndPreserveFeatures() throws {
        let snapshot = try ClaudeUsageNormalizer.snapshot(
            from: fixture("claude-legacy"),
            account: "fixture@example.invalid",
            plan: "Claude Max 20x"
        )

        let session = try XCTUnwrap(snapshot.windows.first(where: { $0.id == "claude-session" }))
        XCTAssertEqual(session.displayMode, .used)
        XCTAssertEqual(session.displayPercent, 34, accuracy: 0.001)
        XCTAssertEqual(session.barFraction, 0.34, accuracy: 0.001)

        XCTAssertTrue(snapshot.windows.contains(where: { $0.title == "All models" && $0.usedPercent == 52 }))
        XCTAssertTrue(snapshot.windows.contains(where: { $0.title == "Sonnet only" }))
        XCTAssertTrue(snapshot.windows.contains(where: { $0.title == "Claude Design" }))
        XCTAssertTrue(snapshot.windows.contains(where: { $0.title == "Cowork" }))
        XCTAssertTrue(snapshot.windows.contains(where: { $0.title == "OAuth apps" }))
        XCTAssertTrue(snapshot.detailSections.contains(where: { $0.id == "claude-extra-usage" }))
    }

    func testClaudeScopedLimitsAreDynamicAndDeduplicateLegacyModels() throws {
        let snapshot = try ClaudeUsageNormalizer.snapshot(
            from: fixture("claude-scoped-limits"),
            account: nil,
            plan: nil
        )

        let weekly = try XCTUnwrap(snapshot.sections.first(where: { $0.id == "claude-weekly-limits" }))
        XCTAssertEqual(weekly.windows.filter { $0.title.lowercased().contains("sonnet") }.count, 1)
        XCTAssertTrue(weekly.windows.contains(where: { $0.title == "Claude Sonnet 4.5 only" }))
        let fable = try XCTUnwrap(weekly.windows.first(where: { $0.title == "Fable only" }))
        XCTAssertEqual(fable.isActive, false)
        XCTAssertFalse(snapshot.windows.contains(where: { $0.title == "All models only" }))

        let features = try XCTUnwrap(snapshot.sections.first(where: { $0.id == "claude-feature-limits" }))
        XCTAssertTrue(features.windows.contains(where: { $0.title == "Daily Routines" }))
        XCTAssertTrue(features.windows.contains(where: { $0.title == "Seven Day Future Feature" }))
        XCTAssertTrue(features.windows.contains(where: { $0.title == "Future model" }))
    }

    func testClaudeAuxiliaryEndpointsNormalizeIntoDetailRows() throws {
        let auxiliary = ClaudeUsageNormalizer.auxiliaryUsage(
            creditsData: try fixture("claude-prepaid-credits"),
            bundlesData: try fixture("claude-prepaid-bundles"),
            routineData: try fixture("claude-routine-budget")
        )
        XCTAssertEqual(auxiliary.prepaidAmount, 3750)
        XCTAssertEqual(auxiliary.autoReloadEnabled, true)
        XCTAssertEqual(auxiliary.pendingInvoiceAmount, 200)
        XCTAssertEqual(auxiliary.routineUsed, 4)
        XCTAssertEqual(auxiliary.routineLimit, 15)
        XCTAssertNotNil(auxiliary.purchasesResetAt)

        let snapshot = try ClaudeUsageNormalizer.snapshot(
            from: fixture("claude-legacy"),
            account: nil,
            plan: nil,
            auxiliary: auxiliary
        )
        let features = try XCTUnwrap(snapshot.detailSections.first(where: { $0.id == "claude-additional-features" }))
        XCTAssertEqual(features.items.first?.value, "4 / 15")
        let extra = try XCTUnwrap(snapshot.detailSections.first(where: { $0.id == "claude-extra-usage" }))
        XCTAssertTrue(extra.items.contains(where: { $0.id == "claude-prepaid-balance" }))
        XCTAssertTrue(extra.items.contains(where: { $0.id == "claude-auto-reload" && $0.value == "On" }))
    }

    func testClaudePlanMappingPreservesMaxMultiplier() {
        XCTAssertEqual(
            ClaudeUsageNormalizer.planDisplayName(
                subscriptionType: "max",
                rateLimitTier: "default_claude_max_20x"
            ),
            "Claude Max 20x"
        )
        XCTAssertEqual(
            ClaudeUsageNormalizer.planDisplayName(subscriptionType: "pro", rateLimitTier: nil),
            "Claude Pro"
        )
    }

    private func fixture(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url, "Missing fixture \(name).json"))
    }
}
