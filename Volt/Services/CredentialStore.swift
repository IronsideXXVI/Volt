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
