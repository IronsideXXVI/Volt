import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private static let selectedProviderKey = "selectedProvider"
    private static let refreshIntervalSeconds: TimeInterval = 10 * 60

    var selectedProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: Self.selectedProviderKey)
        }
    }

    private(set) var snapshots: [AIProvider: ProviderUsageSnapshot] = [:]
    private(set) var errors: [AIProvider: String] = [:]
    private(set) var loadingProviders: Set<AIProvider> = []
    private(set) var configuredProviders: Set<AIProvider> = []

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.selectedProviderKey)
        selectedProvider = AIProvider(rawValue: saved ?? "") ?? .anthropic
        if (try? CredentialStore.loadClaude())?.isComplete == true {
            configuredProviders.insert(.anthropic)
        }
        if (try? CredentialStore.loadOpenAI())?.isComplete == true {
            configuredProviders.insert(.openAI)
        }
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
        configuredProviders.contains(provider)
    }

    @discardableResult
    func refreshSelected() async -> Bool {
        await refresh(selectedProvider)
    }

    @discardableResult
    func refreshIfNeeded(_ provider: AIProvider) async -> Bool {
        if let snapshot = snapshots[provider],
           Date().timeIntervalSince(snapshot.updatedAt) < 60 {
            return true
        }
        return await refresh(provider)
    }

    @discardableResult
    func refresh(_ provider: AIProvider) async -> Bool {
        if loadingProviders.contains(provider) {
            return await waitForRefreshCompletion(provider)
        }
        guard isConfigured(provider) else {
            snapshots[provider] = nil
            errors[provider] = nil
            return false
        }

        loadingProviders.insert(provider)
        errors[provider] = nil
        defer { loadingProviders.remove(provider) }

        do {
            let snapshot: ProviderUsageSnapshot
            switch provider {
            case .anthropic:
                guard let credentials = try CredentialStore.loadClaude() else {
                    throw UsageServiceError.notConfigured(provider)
                }
                let result = try await ClaudeUsageService.fetch(credentials: credentials)
                snapshot = result.snapshot
                if result.credentials != credentials {
                    try CredentialStore.saveClaude(result.credentials)
                }
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

            snapshots[provider] = snapshot.curatedForDashboard()
            errors[provider] = nil
            return true
        } catch is CancellationError {
            return false
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch {
            errors[provider] = error.localizedDescription
            return false
        }
    }

    private func waitForRefreshCompletion(_ provider: AIProvider) async -> Bool {
        while loadingProviders.contains(provider) {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return snapshots[provider] != nil && errors[provider] == nil
    }

    func refreshDelay(for provider: AIProvider, now: Date = Date()) -> Duration {
        let regularInterval = Self.refreshIntervalSeconds
        guard let snapshot = snapshots[provider] else {
            return .seconds(regularInterval)
        }
        let nextReset = snapshot.windows
            .compactMap(\.resetsAt)
            .map { $0.timeIntervalSince(now) }
            .filter { $0 > 0 }
            .min()
        guard let nextReset, nextReset < regularInterval else {
            return .seconds(regularInterval)
        }
        return .seconds(max(nextReset + 2, 15))
    }

    func claudeCredentials() throws -> ClaudeCredentials {
        try CredentialStore.loadClaude() ?? ClaudeCredentials()
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
            configuredProviders.insert(.anthropic)
        } else {
            try CredentialStore.deleteClaude()
            configuredProviders.remove(.anthropic)
        }
        snapshots[.anthropic] = nil
        errors[.anthropic] = nil
    }

    func saveOpenAI(_ credentials: OpenAICredentials) throws {
        if credentials.isComplete {
            try CredentialStore.saveOpenAI(credentials)
            configuredProviders.insert(.openAI)
        } else {
            try CredentialStore.deleteOpenAI()
            configuredProviders.remove(.openAI)
        }
        snapshots[.openAI] = nil
        errors[.openAI] = nil
    }

    func disconnect(_ provider: AIProvider) throws {
        switch provider {
        case .anthropic:
            try CredentialStore.deleteClaude()
        case .openAI:
            try CredentialStore.deleteOpenAI()
        }
        configuredProviders.remove(provider)
        snapshots[provider] = nil
        errors[provider] = nil
    }
}
