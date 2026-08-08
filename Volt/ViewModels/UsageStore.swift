import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private static let selectedAccountKey = "selectedAccountID"
    private static let accountsKey = "providerAccounts"
    private static let showsAccountNumbersKey = "showsAccountNumbers"
    private static let legacySelectedProviderKey = "selectedProvider"
    private static let legacyProviderOrderKey = "providerOrder"
    private let defaults: UserDefaults

    var showsAccountNumbers: Bool {
        didSet {
            defaults.set(showsAccountNumbers, forKey: Self.showsAccountNumbersKey)
        }
    }

    var selectedAccountID: UUID {
        didSet {
            defaults.set(selectedAccountID.uuidString, forKey: Self.selectedAccountKey)
        }
    }

    /// The account profiles and their dashboard-tab order. Only non-secret
    /// metadata is stored in UserDefaults; credentials remain account-scoped
    /// Keychain items.
    private(set) var accounts: [ProviderAccount] {
        didSet {
            if let data = try? JSONEncoder().encode(accounts) {
                defaults.set(data, forKey: Self.accountsKey)
            }
        }
    }

    private(set) var snapshots: [UUID: ProviderUsageSnapshot] = [:]
    private(set) var errors: [UUID: String] = [:]
    private(set) var loadingAccounts: Set<UUID> = []
    private(set) var configuredAccounts: Set<UUID> = []

    init(defaults: UserDefaults = .standard, migrateCredentials: Bool = true) {
        self.defaults = defaults
        let initialShowsAccountNumbers = defaults.object(forKey: Self.showsAccountNumbersKey) == nil
            ? true
            : defaults.bool(forKey: Self.showsAccountNumbersKey)
        showsAccountNumbers = initialShowsAccountNumbers
        defaults.set(initialShowsAccountNumbers, forKey: Self.showsAccountNumbersKey)

        let savedAccounts: [ProviderAccount]
        if let data = defaults.data(forKey: Self.accountsKey),
           let decoded = try? JSONDecoder().decode([ProviderAccount].self, from: data),
           !decoded.isEmpty {
            var normalized = decoded
            for provider in AIProvider.allCases where !normalized.contains(where: { $0.provider == provider }) {
                normalized.append(ProviderAccount(provider: provider))
            }
            savedAccounts = normalized
        } else {
            savedAccounts = Self.initialAccounts(defaults: defaults)
        }
        if let data = try? JSONEncoder().encode(savedAccounts) {
            defaults.set(data, forKey: Self.accountsKey)
        }
        accounts = savedAccounts

        let savedSelection = defaults.string(forKey: Self.selectedAccountKey).flatMap(UUID.init(uuidString:))
        let legacyProvider = defaults.string(forKey: Self.legacySelectedProviderKey)
            .flatMap(AIProvider.init(rawValue:))
        selectedAccountID = savedSelection.flatMap { id in
            savedAccounts.contains(where: { $0.id == id }) ? id : nil
        } ?? savedAccounts.first(where: { $0.provider == legacyProvider })?.id
            ?? savedAccounts[0].id
        defaults.set(selectedAccountID.uuidString, forKey: Self.selectedAccountKey)

        if migrateCredentials {
            try? CredentialStore.migrateLegacyCredentials(to: savedAccounts)
            for account in savedAccounts where credentialsAreComplete(for: account) {
                configuredAccounts.insert(account.id)
            }
        }
    }

    var selectedAccount: ProviderAccount {
        account(for: selectedAccountID) ?? accounts[0]
    }

    var selectedProvider: AIProvider {
        selectedAccount.provider
    }

    func account(for id: UUID) -> ProviderAccount? {
        accounts.first { $0.id == id }
    }

    func accounts(for provider: AIProvider) -> [ProviderAccount] {
        accounts.filter { $0.provider == provider }
    }

    func accountOrdinal(for accountID: UUID) -> Int? {
        accounts.firstIndex(where: { $0.id == accountID }).map { $0 + 1 }
    }

    func accountOrdinal(for account: ProviderAccount) -> Int? {
        accountOrdinal(for: account.id)
    }

    func accountLabel(for accountID: UUID) -> String {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else {
            return "Account"
        }
        return "\(accounts[index].provider.displayName) account \(index + 1)"
    }

    func accountLabel(for account: ProviderAccount) -> String {
        accountLabel(for: account.id)
    }

    func snapshot(for accountID: UUID) -> ProviderUsageSnapshot? {
        snapshots[accountID]
    }

    func error(for accountID: UUID) -> String? {
        errors[accountID]
    }

    func isLoading(_ accountID: UUID) -> Bool {
        loadingAccounts.contains(accountID)
    }

    func isConfigured(_ accountID: UUID) -> Bool {
        configuredAccounts.contains(accountID)
    }

    @discardableResult
    func addAccount(provider: AIProvider) -> ProviderAccount {
        let account = ProviderAccount(provider: provider)
        accounts.append(account)
        selectedAccountID = account.id
        return account
    }

    func reorderAccount(_ accountID: UUID, toSlotOf targetID: UUID) {
        guard accountID != targetID,
              let from = accounts.firstIndex(where: { $0.id == accountID }),
              let to = accounts.firstIndex(where: { $0.id == targetID })
        else { return }
        let moved = accounts.remove(at: from)
        accounts.insert(moved, at: min(to, accounts.count))
    }

    func removeAccount(_ accountID: UUID) throws {
        guard let account = account(for: accountID),
              accounts(for: account.provider).count > 1
        else { return }

        try deleteCredentials(for: account)
        accounts.removeAll { $0.id == accountID }
        configuredAccounts.remove(accountID)
        snapshots[accountID] = nil
        errors[accountID] = nil
        loadingAccounts.remove(accountID)
        if selectedAccountID == accountID {
            selectedAccountID = accounts.first(where: { $0.provider == account.provider })?.id
                ?? accounts[0].id
        }
    }

    @discardableResult
    func refreshSelected() async -> Bool {
        await refresh(selectedAccountID)
    }

    /// Fetches every configured account once. Called when the menu opens so
    /// every tab is fresh without fetching again on tab switch.
    func refreshOnOpen() async {
        var accountIDs = [selectedAccountID]
        accountIDs.append(contentsOf: accounts.map(\.id).filter { $0 != selectedAccountID })
        for accountID in accountIDs where isConfigured(accountID) {
            await refresh(accountID)
        }
    }

    /// - Parameter forceTokenRefresh: Ask the provider to rotate the stored
    ///   refresh token before fetching, even when the access token is still
    ///   valid. Set by the Settings connection test so a freshly imported
    ///   credential never sits on the token its `codex login` minted.
    @discardableResult
    func refresh(_ accountID: UUID, forceTokenRefresh: Bool = false) async -> Bool {
        if loadingAccounts.contains(accountID) {
            return await waitForRefreshCompletion(accountID)
        }
        guard let account = account(for: accountID), isConfigured(accountID) else {
            snapshots[accountID] = nil
            errors[accountID] = nil
            return false
        }

        loadingAccounts.insert(accountID)
        errors[accountID] = nil
        defer { loadingAccounts.remove(accountID) }

        do {
            let snapshot: ProviderUsageSnapshot
            switch account.provider {
            case .anthropic:
                guard let credentials = try CredentialStore.loadClaude(accountID: accountID) else {
                    throw UsageServiceError.notConfigured(account.provider)
                }
                let result = try await ClaudeUsageService.fetch(credentials: credentials)
                snapshot = result.snapshot
                if result.credentials != credentials {
                    try CredentialStore.saveClaude(result.credentials, accountID: accountID)
                }
            case .openAI:
                guard let credentials = try CredentialStore.loadOpenAI(accountID: accountID) else {
                    throw UsageServiceError.notConfigured(account.provider)
                }
                let result = try await OpenAIUsageService.fetch(
                    credentials: credentials,
                    forceTokenRefresh: forceTokenRefresh
                )
                snapshot = result.snapshot
                if result.credentials != credentials {
                    try CredentialStore.saveOpenAI(result.credentials, accountID: accountID)
                }
            }

            snapshots[accountID] = snapshot.curatedForDashboard()
            errors[accountID] = nil
            return true
        } catch is CancellationError {
            return false
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch {
            errors[accountID] = error.localizedDescription
            return false
        }
    }

    private func waitForRefreshCompletion(_ accountID: UUID) async -> Bool {
        while loadingAccounts.contains(accountID) {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return snapshots[accountID] != nil && errors[accountID] == nil
    }

    func claudeCredentials(accountID: UUID) throws -> ClaudeCredentials {
        try CredentialStore.loadClaude(accountID: accountID) ?? ClaudeCredentials()
    }

    func openAICredentials(accountID: UUID) throws -> OpenAICredentials {
        try CredentialStore.loadOpenAI(accountID: accountID) ?? Self.emptyOpenAICredentials
    }

    func saveClaude(_ credentials: ClaudeCredentials, accountID: UUID) throws {
        guard account(for: accountID)?.provider == .anthropic else { return }
        if credentials.isComplete {
            try CredentialStore.saveClaude(credentials, accountID: accountID)
            configuredAccounts.insert(accountID)
        } else {
            try CredentialStore.deleteClaude(accountID: accountID)
            configuredAccounts.remove(accountID)
        }
        snapshots[accountID] = nil
        errors[accountID] = nil
    }

    func saveOpenAI(_ credentials: OpenAICredentials, accountID: UUID) throws {
        guard account(for: accountID)?.provider == .openAI else { return }
        if credentials.isComplete {
            try CredentialStore.saveOpenAI(credentials, accountID: accountID)
            configuredAccounts.insert(accountID)
        } else {
            try CredentialStore.deleteOpenAI(accountID: accountID)
            configuredAccounts.remove(accountID)
        }
        snapshots[accountID] = nil
        errors[accountID] = nil
    }

    func disconnect(_ accountID: UUID) throws {
        guard let account = account(for: accountID) else { return }
        try deleteCredentials(for: account)
        configuredAccounts.remove(accountID)
        snapshots[accountID] = nil
        errors[accountID] = nil
    }

    private func credentialsAreComplete(for account: ProviderAccount) -> Bool {
        switch account.provider {
        case .anthropic:
            return (try? CredentialStore.loadClaude(accountID: account.id))?.isComplete == true
        case .openAI:
            return (try? CredentialStore.loadOpenAI(accountID: account.id))?.isComplete == true
        }
    }

    private func deleteCredentials(for account: ProviderAccount) throws {
        switch account.provider {
        case .anthropic:
            try CredentialStore.deleteClaude(accountID: account.id)
        case .openAI:
            try CredentialStore.deleteOpenAI(accountID: account.id)
        }
    }

    private static func initialAccounts(defaults: UserDefaults) -> [ProviderAccount] {
        let savedOrder = (defaults.array(forKey: legacyProviderOrderKey) as? [String]) ?? []
        var providerOrder = savedOrder.compactMap(AIProvider.init(rawValue:))
        for provider in AIProvider.allCases where !providerOrder.contains(provider) {
            providerOrder.append(provider)
        }
        return providerOrder.map { ProviderAccount(provider: $0) }
    }

    private static let emptyOpenAICredentials = OpenAICredentials(
        accessToken: "",
        refreshToken: "",
        idToken: "",
        accountID: "",
        lastRefresh: nil
    )
}
