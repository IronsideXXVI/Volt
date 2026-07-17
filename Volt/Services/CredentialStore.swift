import Foundation
import Security

struct ClaudeCredentials: Codable, Equatable, Sendable {
    var organizationID: String
    var sessionKey: String

    var isComplete: Bool {
        !organizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        if let expiration = payload?["exp"] as? Double {
            return Date(timeIntervalSince1970: expiration)
        }
        if let expiration = payload?["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(expiration))
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
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any]
        else {
            throw CredentialStoreError.invalidCodexFile
        }

        func value(_ snakeCase: String, _ camelCase: String) -> String {
            (tokens[snakeCase] as? String) ?? (tokens[camelCase] as? String) ?? ""
        }

        let accessToken = value("access_token", "accessToken")
        guard !accessToken.isEmpty else {
            throw CredentialStoreError.invalidCodexFile
        }

        let lastRefresh: Date?
        if let rawDate = root["last_refresh"] as? String {
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

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)
    case invalidCodexFile

    var errorDescription: String? {
        switch self {
        case let .keychain(status):
            if let message = SecCopyErrorMessageString(status, nil) as? String {
                return "Keychain error: \(message)"
            }
            return "Keychain error \(status)."
        case .invalidCodexFile:
            return "That file does not contain Codex OAuth credentials. Choose ~/.codex/auth.json after signing in with Codex."
        }
    }
}

enum CredentialStore {
    private static let service = "com.IronsideXXVI.Volt.credentials"
    private static let claudeAccount = "anthropic"
    private static let openAIAccount = "openai"

    static func loadClaude() throws -> ClaudeCredentials? {
        try load(ClaudeCredentials.self, account: claudeAccount)
    }

    static func saveClaude(_ credentials: ClaudeCredentials) throws {
        try save(credentials, account: claudeAccount)
    }

    static func deleteClaude() throws {
        try delete(account: claudeAccount)
    }

    static func loadOpenAI() throws -> OpenAICredentials? {
        try load(OpenAICredentials.self, account: openAIAccount)
    }

    static func saveOpenAI(_ credentials: OpenAICredentials) throws {
        try save(credentials, account: openAIAccount)
    }

    static func deleteOpenAI() throws {
        try delete(account: openAIAccount)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, account: String) throws -> Value? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialStoreError.keychain(status)
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private static func save<Value: Encodable>(_ value: Value, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialStoreError.keychain(updateStatus)
        }
    }

    private static func delete(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
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
