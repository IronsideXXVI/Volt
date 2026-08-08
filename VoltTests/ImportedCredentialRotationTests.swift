import XCTest
@testable import Volt

/// Documents the gap that `forceTokenRefresh` closes.
///
/// `codex login` mints a refresh token and an access token that stays valid for
/// days. OpenAI revokes the refresh token issued by the previous `codex login`
/// on a machine, so a second login -- even for an unrelated account -- kills the
/// first one's token. Volt only refreshes within five minutes of expiry, so an
/// imported credential would otherwise sit on that revocable login token for its
/// entire lifetime. Exchanging it once at import time moves Volt onto a
/// descendant token, which a later login leaves alone.
final class ImportedCredentialRotationTests: XCTestCase {
    /// Builds an unsigned JWT whose payload carries the given expiry, matching
    /// what `JWT.payload(from:)` reads.
    private func accessToken(expiringIn interval: TimeInterval) -> String {
        let exp = Int(Date().addingTimeInterval(interval).timeIntervalSince1970)
        let payload = try! JSONSerialization.data(withJSONObject: ["exp": exp])
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    private func credentials(expiringIn interval: TimeInterval) -> OpenAICredentials {
        OpenAICredentials(
            accessToken: accessToken(expiringIn: interval),
            refreshToken: "refresh-token",
            idToken: "",
            accountID: "account-id",
            lastRefresh: Date()
        )
    }

    /// The vulnerability window: a credential straight out of `codex login` is
    /// not due for refresh, so without an explicit rotation it keeps the exact
    /// token a later login revokes.
    func testFreshlyImportedCredentialIsNotDueForRefresh() {
        XCTAssertFalse(credentials(expiringIn: 10 * 24 * 60 * 60).shouldRefresh)
        XCTAssertFalse(credentials(expiringIn: 60 * 60).shouldRefresh)
    }

    func testCredentialNearingExpiryIsDueForRefresh() {
        XCTAssertTrue(credentials(expiringIn: 60).shouldRefresh)
        XCTAssertTrue(credentials(expiringIn: -60).shouldRefresh)
    }

    /// A forced refresh must never be attempted without something to exchange,
    /// so access-token-only setups keep working.
    func testCredentialWithoutRefreshTokenIsNeverDueForRefresh() {
        let manual = OpenAICredentials(
            accessToken: accessToken(expiringIn: -60),
            refreshToken: "",
            idToken: "",
            accountID: "account-id",
            lastRefresh: nil
        )
        XCTAssertFalse(manual.shouldRefresh)
    }
}
