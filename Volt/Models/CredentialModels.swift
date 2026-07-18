import Foundation

struct ClaudeCredentials: Codable, Equatable, Sendable {
    var organizationID: String
    var sessionKey: String
    var oauthAccessToken: String?
    var oauthRefreshToken: String?
    var oauthExpiresAt: Date?
    var oauthScopes: [String]?
    var oauthRateLimitTier: String?
    var oauthSubscriptionType: String?

    init(
        organizationID: String = "",
        sessionKey: String = "",
        oauthAccessToken: String? = nil,
        oauthRefreshToken: String? = nil,
        oauthExpiresAt: Date? = nil,
        oauthScopes: [String]? = nil,
        oauthRateLimitTier: String? = nil,
        oauthSubscriptionType: String? = nil
    ) {
        self.organizationID = organizationID
        self.sessionKey = sessionKey
        self.oauthAccessToken = oauthAccessToken
        self.oauthRefreshToken = oauthRefreshToken
        self.oauthExpiresAt = oauthExpiresAt
        self.oauthScopes = oauthScopes
        self.oauthRateLimitTier = oauthRateLimitTier
        self.oauthSubscriptionType = oauthSubscriptionType
    }

    var hasWebCredentials: Bool {
        !organizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasOAuthCredentials: Bool {
        !(oauthAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var isComplete: Bool {
        hasOAuthCredentials || hasWebCredentials
    }

    var shouldRefreshOAuth: Bool {
        guard hasOAuthCredentials,
              !(oauthRefreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        else {
            return false
        }
        guard let oauthExpiresAt else { return false }
        return oauthExpiresAt.timeIntervalSinceNow < 5 * 60
    }

    static func imported(from data: Data) throws -> ClaudeCredentials {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any]
        else {
            throw CredentialImportError.invalidClaudeFile
        }

        let accessToken = (oauth["accessToken"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !accessToken.isEmpty else {
            throw CredentialImportError.invalidClaudeFile
        }

        let expiresAt: Date?
        if let raw = flexibleDouble(oauth["expiresAt"]) {
            expiresAt = Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
        } else {
            expiresAt = nil
        }

        return ClaudeCredentials(
            oauthAccessToken: accessToken,
            oauthRefreshToken: oauth["refreshToken"] as? String,
            oauthExpiresAt: expiresAt,
            oauthScopes: oauth["scopes"] as? [String],
            oauthRateLimitTier: oauth["rateLimitTier"] as? String,
            oauthSubscriptionType: oauth["subscriptionType"] as? String
        )
    }
}

struct OpenAICredentials: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var accountID: String
    var lastRefresh: Date?

    var isComplete: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var accountEmail: String? {
        let payload = JWT.payload(from: idToken) ?? JWT.payload(from: accessToken)
        let profile = payload?["https://api.openai.com/profile"] as? [String: Any]
        return (payload?["email"] as? String) ?? (profile?["email"] as? String)
    }

    var tokenPlan: String? {
        let payload = JWT.payload(from: idToken) ?? JWT.payload(from: accessToken)
        let authentication = payload?["https://api.openai.com/auth"] as? [String: Any]
        return (authentication?["chatgpt_plan_type"] as? String)
            ?? (payload?["chatgpt_plan_type"] as? String)
    }

    var tokenExpiration: Date? {
        let payload = JWT.payload(from: accessToken)
        if let expiration = flexibleDouble(payload?["exp"]) {
            return Date(timeIntervalSince1970: expiration)
        }
        return nil
    }

    var shouldRefresh: Bool {
        guard !refreshToken.isEmpty else { return false }
        if let tokenExpiration {
            return tokenExpiration.timeIntervalSinceNow < 5 * 60
        }
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > 7 * 24 * 60 * 60
    }

    static func imported(from data: Data) throws -> OpenAICredentials {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialImportError.invalidCodexFile
        }
        let tokens = (root["tokens"] as? [String: Any]) ?? root

        func value(_ snakeCase: String, _ camelCase: String) -> String {
            (tokens[snakeCase] as? String)
                ?? (tokens[camelCase] as? String)
                ?? (root[snakeCase] as? String)
                ?? (root[camelCase] as? String)
                ?? ""
        }

        let accessToken = value("access_token", "accessToken")
        guard !accessToken.isEmpty else {
            throw CredentialImportError.invalidCodexFile
        }

        let lastRefresh: Date?
        if let rawDate = (root["last_refresh"] as? String) ?? (root["lastRefresh"] as? String) {
            lastRefresh = ISO8601.date(from: rawDate)
        } else {
            lastRefresh = nil
        }

        return OpenAICredentials(
            accessToken: accessToken,
            refreshToken: value("refresh_token", "refreshToken"),
            idToken: value("id_token", "idToken"),
            accountID: value("account_id", "accountId"),
            lastRefresh: lastRefresh
        )
    }
}

enum CredentialImportError: LocalizedError {
    case invalidClaudeFile
    case invalidCodexFile

    var errorDescription: String? {
        switch self {
        case .invalidClaudeFile:
            return "That file does not contain Claude Code OAuth credentials. Run `claude login`, then choose ~/.claude/.credentials.json."
        case .invalidCodexFile:
            return "That file does not contain Codex OAuth credentials. Run `codex login`, then choose ~/.codex/auth.json."
        }
    }
}

enum JWT {
    static func payload(from token: String) -> [String: Any]? {
        let components = token.split(separator: ".")
        guard components.count > 1 else { return nil }
        var encoded = String(components[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder != 0 {
            encoded += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }
}

enum ISO8601 {
    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private func flexibleDouble(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber:
        return number.doubleValue
    case let string as String:
        return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
    default:
        return nil
    }
}
