import Foundation
import Security

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .keychain(status):
            if let message = SecCopyErrorMessageString(status, nil) as? String {
                return "Keychain error: \(message)"
            }
            return "Keychain error \(status)."
        }
    }
}

enum CredentialStore {
    private static let service = "com.IronsideXXVI.Volt.credentials"
    private static let legacyClaudeAccount = "anthropic"
    private static let legacyOpenAIAccount = "openai"

    static func loadClaude(accountID: UUID) throws -> ClaudeCredentials? {
        try load(ClaudeCredentials.self, account: keychainAccount(provider: .anthropic, accountID: accountID))
    }

    static func saveClaude(_ credentials: ClaudeCredentials, accountID: UUID) throws {
        try save(credentials, account: keychainAccount(provider: .anthropic, accountID: accountID))
    }

    static func deleteClaude(accountID: UUID) throws {
        try delete(account: keychainAccount(provider: .anthropic, accountID: accountID))
    }

    static func loadOpenAI(accountID: UUID) throws -> OpenAICredentials? {
        try load(OpenAICredentials.self, account: keychainAccount(provider: .openAI, accountID: accountID))
    }

    static func saveOpenAI(_ credentials: OpenAICredentials, accountID: UUID) throws {
        try save(credentials, account: keychainAccount(provider: .openAI, accountID: accountID))
    }

    static func deleteOpenAI(accountID: UUID) throws {
        try delete(account: keychainAccount(provider: .openAI, accountID: accountID))
    }

    /// Moves the pre-multi-account Keychain entries into the first profile for
    /// each provider. The copy happens before the legacy item is removed, so an
    /// interrupted migration never loses credentials.
    static func migrateLegacyCredentials(to accounts: [ProviderAccount]) throws {
        if let target = accounts.first(where: { $0.provider == .anthropic }),
           let credentials = try load(ClaudeCredentials.self, account: legacyClaudeAccount) {
            if try loadClaude(accountID: target.id) == nil {
                try saveClaude(credentials, accountID: target.id)
            }
            try delete(account: legacyClaudeAccount)
        }

        if let target = accounts.first(where: { $0.provider == .openAI }),
           let credentials = try load(OpenAICredentials.self, account: legacyOpenAIAccount) {
            if try loadOpenAI(accountID: target.id) == nil {
                try saveOpenAI(credentials, accountID: target.id)
            }
            try delete(account: legacyOpenAIAccount)
        }
    }

    private static func keychainAccount(provider: AIProvider, accountID: UUID) -> String {
        "\(provider.rawValue).\(accountID.uuidString.lowercased())"
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
