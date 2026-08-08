import XCTest
@testable import Volt

/// Pins when an OpenAI credential is considered due for a token exchange.
///
/// The threshold is deliberately narrow. Volt and Codex hold the same refresh
/// token immediately after an `auth.json` import, and a refresh token may only
/// be redeemed once -- so any exchange Volt performs spends the copy still on
/// disk in `~/.codex`. Refreshing only at the edge of expiry keeps that window
/// small; refreshing eagerly would spend Codex's copy immediately and invite
/// reuse detection to revoke the whole family. Anyone importing a credential
/// should re-run `codex login` so the two clients stop sharing a session.
final class CredentialRefreshThresholdTests: XCTestCase {
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

    /// A credential with life left in it must be left alone, so Volt does not
    /// spend a refresh token that Codex is still relying on.
    func testCredentialWithTimeRemainingIsNotRefreshed() {
        XCTAssertFalse(credentials(expiringIn: 10 * 24 * 60 * 60).shouldRefresh)
        XCTAssertFalse(credentials(expiringIn: 60 * 60).shouldRefresh)
    }

    func testCredentialNearingExpiryIsRefreshed() {
        XCTAssertTrue(credentials(expiringIn: 60).shouldRefresh)
        XCTAssertTrue(credentials(expiringIn: -60).shouldRefresh)
    }

    /// Access-token-only setups have nothing to exchange and must never be
    /// treated as refreshable.
    func testCredentialWithoutRefreshTokenIsNeverRefreshed() {
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
