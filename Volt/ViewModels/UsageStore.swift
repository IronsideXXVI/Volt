import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private static let selectedProviderKey = "selectedProvider"
    static let refreshInterval: Duration = .seconds(10 * 60)

    var selectedProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: Self.selectedProviderKey)
        }
    }

    private(set) var snapshots: [AIProvider: ProviderUsageSnapshot] = [:]
    private(set) var errors: [AIProvider: String] = [:]
    private(set) var loadingProviders: Set<AIProvider> = []

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.selectedProviderKey)
        selectedProvider = AIProvider(rawValue: saved ?? "") ?? .anthropic
    }

    func snapshot(for provider: AIProvider) -> ProviderUsageSnapshot? {
        snapshots[provider]
    }

    func error(for provider: AIProvider) -> String? {
        errors[provider]
    }

    func isLoading(_ provider: AIProvider) -> Bool {
        loadingProviders.contains(provider)
    }

    func isConfigured(_ provider: AIProvider) -> Bool {
        switch provider {
        case .anthropic:
            return (try? CredentialStore.loadClaude())?.isComplete == true
        case .openAI:
            return (try? CredentialStore.loadOpenAI())?.isComplete == true
        }
    }

    func refreshSelected() async {
        await refresh(selectedProvider)
    }

    func refreshIfNeeded(_ provider: AIProvider) async {
        if let snapshot = snapshots[provider],
           Date().timeIntervalSince(snapshot.updatedAt) < 60 {
            return
        }
        await refresh(provider)
    }

    func refresh(_ provider: AIProvider) async {
        guard !loadingProviders.contains(provider) else { return }
        guard isConfigured(provider) else {
            snapshots[provider] = nil
            errors[provider] = nil
            return
        }

        loadingProviders.insert(provider)
        defer { loadingProviders.remove(provider) }

        do {
            let snapshot: ProviderUsageSnapshot
            switch provider {
            case .anthropic:
                guard let credentials = try CredentialStore.loadClaude() else {
                    throw UsageServiceError.notConfigured(provider)
                }
                snapshot = try await ClaudeUsageService.fetch(credentials: credentials)
            case .openAI:
                guard let credentials = try CredentialStore.loadOpenAI() else {
                    throw UsageServiceError.notConfigured(provider)
                }
                let result = try await OpenAIUsageService.fetch(credentials: credentials)
                snapshot = result.snapshot
                if result.credentials != credentials {
                    try CredentialStore.saveOpenAI(result.credentials)
                }
            }

            snapshots[provider] = snapshot
            errors[provider] = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            errors[provider] = error.localizedDescription
        }
    }

    func claudeCredentials() throws -> ClaudeCredentials {
        try CredentialStore.loadClaude() ?? ClaudeCredentials(organizationID: "", sessionKey: "")
    }

    func openAICredentials() throws -> OpenAICredentials {
        try CredentialStore.loadOpenAI() ?? OpenAICredentials(
            accessToken: "",
            refreshToken: "",
            idToken: "",
            accountID: "",
            lastRefresh: nil
        )
    }

    func saveClaude(_ credentials: ClaudeCredentials) throws {
        if credentials.isComplete {
            try CredentialStore.saveClaude(credentials)
        } else {
            try CredentialStore.deleteClaude()
            snapshots[.anthropic] = nil
        }
        errors[.anthropic] = nil
    }

    func saveOpenAI(_ credentials: OpenAICredentials) throws {
        if credentials.isComplete {
            try CredentialStore.saveOpenAI(credentials)
        } else {
            try CredentialStore.deleteOpenAI()
            snapshots[.openAI] = nil
        }
        errors[.openAI] = nil
    }

    func disconnect(_ provider: AIProvider) throws {
        switch provider {
        case .anthropic:
            try CredentialStore.deleteClaude()
        case .openAI:
            try CredentialStore.deleteOpenAI()
        }
        snapshots[provider] = nil
        errors[provider] = nil
    }
}
