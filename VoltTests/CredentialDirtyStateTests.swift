import XCTest
@testable import Volt

/// Locks the Settings "unsaved changes" invariant: loading a stored credential
/// set and re-deriving the editable draft from it must compare equal, so a
/// pristine load never shows as dirty. The Settings view copies stored
/// credentials into editable string/array state (mapping `nil` -> `""` / `[]`);
/// these helpers reproduce that lossy step so the whole round-trip is covered.
final class CredentialDirtyStateTests: XCTestCase {
    /// Mirrors `SettingsView.applyClaudeCredentials` followed by
    /// `draftClaudeCredentials`: absent optionals become empty strings/arrays in
    /// editable state, then the draft is canonicalized for comparison.
    private func reloadedClaudeDraft(_ stored: ClaudeCredentials) -> ClaudeCredentials {
        ClaudeCredentials(
            organizationID: stored.organizationID,
            sessionKey: stored.sessionKey,
            oauthAccessToken: stored.oauthAccessToken ?? "",
            oauthRefreshToken: stored.oauthRefreshToken ?? "",
            oauthExpiresAt: stored.oauthExpiresAt,
            oauthScopes: stored.oauthScopes ?? [],
            oauthRateLimitTier: stored.oauthRateLimitTier,
            oauthSubscriptionType: stored.oauthSubscriptionType
        ).canonical
    }

    private func reloadedOpenAIDraft(_ stored: OpenAICredentials) -> OpenAICredentials {
        OpenAICredentials(
            accessToken: stored.accessToken,
            refreshToken: stored.refreshToken,
            idToken: stored.idToken,
            accountID: stored.accountID,
            lastRefresh: stored.lastRefresh
        ).canonical
    }

    func testBrowserSessionClaudeIsNotDirtyAfterLoad() {
        let stored = ClaudeCredentials(
            organizationID: "11111111-2222-3333-4444-555555555555",
            sessionKey: "sk-ant-sid01-browser-session-value"
        )
        XCTAssertEqual(reloadedClaudeDraft(stored), stored.canonical)
    }

    func testSessionKeyWithTrailingWhitespaceIsNotDirtyAfterLoad() {
        let stored = ClaudeCredentials(
            organizationID: " org-with-spaces ",
            sessionKey: "sk-ant-sid01-value\n"
        )
        XCTAssertEqual(reloadedClaudeDraft(stored), stored.canonical)
    }

    func testOAuthClaudeWithScopesIsNotDirtyAfterLoad() {
        let stored = ClaudeCredentials(
            oauthAccessToken: "oauth-access",
            oauthRefreshToken: "oauth-refresh",
            oauthExpiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            oauthScopes: ["user:inference", "user:profile"],
            oauthRateLimitTier: "default",
            oauthSubscriptionType: "max"
        )
        XCTAssertEqual(reloadedClaudeDraft(stored), stored.canonical)
    }

    func testEmptyScopesAndNilScopesCanonicalizeEqual() {
        let nilScopes = ClaudeCredentials(organizationID: "o", sessionKey: "s")
        let emptyScopes = ClaudeCredentials(organizationID: "o", sessionKey: "s", oauthScopes: [])
        XCTAssertEqual(nilScopes.canonical, emptyScopes.canonical)
    }

    func testOpenAIWithWhitespaceIsNotDirtyAfterLoad() {
        let stored = OpenAICredentials(
            accessToken: "access-token\n",
            refreshToken: " refresh ",
            idToken: "id-token",
            accountID: "acct-123",
            lastRefresh: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(reloadedOpenAIDraft(stored), stored.canonical)
    }
}
