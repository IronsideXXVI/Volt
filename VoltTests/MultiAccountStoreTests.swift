import XCTest
@testable import Volt

@MainActor
final class MultiAccountStoreTests: XCTestCase {
    func testAccountProfilesPersistNamesOrderAndSelection() {
        let suiteName = "MultiAccountStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults, migrateCredentials: false)
        XCTAssertEqual(store.accounts.map(\.provider), [.anthropic, .openAI])

        let added = store.addAccount(provider: .openAI)
        store.renameAccount(added.id, to: "Work")
        store.reorderAccount(added.id, toSlotOf: store.accounts[0].id)
        store.selectedAccountID = added.id

        let reloaded = UsageStore(defaults: defaults, migrateCredentials: false)
        XCTAssertEqual(reloaded.accounts.first?.id, added.id)
        XCTAssertEqual(reloaded.accounts.first?.displayName, "Work")
        XCTAssertEqual(reloaded.selectedAccountID, added.id)
        XCTAssertEqual(reloaded.accounts(for: .openAI).count, 2)
    }

    func testAddedAccountsReceiveDistinctDefaultTabNames() {
        let suiteName = "MultiAccountStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults, migrateCredentials: false)
        let second = store.addAccount(provider: .anthropic)
        let third = store.addAccount(provider: .anthropic)

        XCTAssertEqual(second.displayName, "Claude 2")
        XCTAssertEqual(third.displayName, "Claude 3")
        XCTAssertEqual(Set(store.accounts(for: .anthropic).map(\.displayName)).count, 3)
    }

    func testLegacyProviderOrderAndSelectionSeedInitialAccounts() {
        let suiteName = "MultiAccountStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([AIProvider.openAI.rawValue, AIProvider.anthropic.rawValue], forKey: "providerOrder")
        defaults.set(AIProvider.openAI.rawValue, forKey: "selectedProvider")

        let store = UsageStore(defaults: defaults, migrateCredentials: false)

        XCTAssertEqual(store.accounts.map(\.provider), [.openAI, .anthropic])
        XCTAssertEqual(store.selectedProvider, .openAI)
    }
}
