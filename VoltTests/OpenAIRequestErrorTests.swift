import XCTest
@testable import Volt

/// Locks the distinction between the two HTTP statuses the ChatGPT usage
/// endpoint uses to refuse a request. A 401 means the token was rejected and
/// the user genuinely has to re-import. A 403 is routinely bot protection or a
/// blocked network path and says nothing about the credentials -- reporting it
/// as "rejected the saved credentials" sends users to re-import a working
/// token, which is how a transient failure used to look like a broken account.
final class OpenAIRequestErrorTests: XCTestCase {
    private func message(_ error: UsageServiceError) -> String {
        error.errorDescription ?? ""
    }

    func testUnauthorizedIsReportedAsRejectedCredentials() {
        let mapped = OpenAIRequestError.unauthorized.usageServiceError
        guard case let .invalidCredentials(provider) = mapped else {
            return XCTFail("401 must map to invalidCredentials, got \(mapped)")
        }
        XCTAssertEqual(provider, .openAI)
        XCTAssertTrue(message(mapped).contains("rejected the saved credentials"))
    }

    func testForbiddenIsNotReportedAsCredentialFailure() {
        let mapped = OpenAIRequestError.forbidden.usageServiceError
        guard case let .server(provider, status) = mapped else {
            return XCTFail("403 must map to a server error, got \(mapped)")
        }
        XCTAssertEqual(provider, .openAI)
        XCTAssertEqual(status, 403)
        XCTAssertFalse(
            message(mapped).contains("rejected the saved credentials"),
            "A 403 must never tell the user their credentials were rejected."
        )
    }

    func testRateLimitAndServerStatusesArePreserved() {
        let retryAfter = Date(timeIntervalSince1970: 1_800_000_000)
        guard case let .rateLimited(provider, date) = OpenAIRequestError
            .rateLimited(retryAfter).usageServiceError
        else {
            return XCTFail("429 must map to rateLimited")
        }
        XCTAssertEqual(provider, .openAI)
        XCTAssertEqual(date, retryAfter)

        guard case let .server(_, status) = OpenAIRequestError.status(503).usageServiceError else {
            return XCTFail("Other statuses must map to server errors")
        }
        XCTAssertEqual(status, 503)

        guard case .invalidResponse = OpenAIRequestError.invalidResponse.usageServiceError else {
            return XCTFail("Undecodable bodies must map to invalidResponse")
        }
    }

    /// Both refusal statuses are worth one refresh-and-retry; nothing else is,
    /// because a new access token cannot clear a rate limit or a 5xx.
    func testOnlyRefusalStatusesTriggerARetry() {
        XCTAssertTrue(OpenAIRequestError.unauthorized.isRetryableWithFreshToken)
        XCTAssertTrue(OpenAIRequestError.forbidden.isRetryableWithFreshToken)
        XCTAssertFalse(OpenAIRequestError.rateLimited(nil).isRetryableWithFreshToken)
        XCTAssertFalse(OpenAIRequestError.status(500).isRetryableWithFreshToken)
        XCTAssertFalse(OpenAIRequestError.invalidResponse.isRetryableWithFreshToken)
    }
}
