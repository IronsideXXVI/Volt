import XCTest
@testable import Volt

@MainActor
final class MultiAccountStoreTests: XCTestCase {
    func testAddedAccountsAppendSelectAndReceiveGlobalOrdinals() {
        withIsolatedDefaults { defaults in
            let store = UsageStore(defaults: defaults, migrateCredentials: false)

            XCTAssertEqual(store.accounts.map(\.provider), [.anthropic, .openAI])
            XCTAssertEqual(store.accounts.map { store.accountOrdinal(for: $0.id) }, [1, 2])
            XCTAssertEqual(
                store.accounts.map { store.accountLabel(for: $0.id) },
                ["Claude account 1", "OpenAI account 2"]
            )

            let third = store.addAccount(provider: .anthropic)
            XCTAssertEqual(store.selectedAccountID, third.id)
            XCTAssertEqual(store.accountOrdinal(for: third), 3)
            XCTAssertEqual(store.accountLabel(for: third), "Claude account 3")

            let fourth = store.addAccount(provider: .openAI)
            XCTAssertEqual(store.selectedAccountID, fourth.id)
            XCTAssertEqual(store.accountOrdinal(for: fourth), 4)
            XCTAssertEqual(store.accountLabel(for: fourth), "OpenAI account 4")
        }
    }

    func testGlobalOrdinalsCompactAfterReorderAndMiddleRemoval() throws {
        try withIsolatedDefaults { defaults in
            let store = UsageStore(defaults: defaults, migrateCredentials: false)
            let firstClaude = store.accounts[0]
            let firstOpenAI = store.accounts[1]
            let secondClaude = store.addAccount(provider: .anthropic)
            let secondOpenAI = store.addAccount(provider: .openAI)

            store.reorderAccount(secondOpenAI.id, toSlotOf: firstClaude.id)

            XCTAssertEqual(
                store.accounts.map(\.id),
                [secondOpenAI.id, firstClaude.id, firstOpenAI.id, secondClaude.id]
            )
            XCTAssertEqual(
                store.accounts.map { store.accountLabel(for: $0.id) },
                [
                    "OpenAI account 1",
                    "Claude account 2",
                    "OpenAI account 3",
                    "Claude account 4",
                ]
            )

            try store.removeAccount(firstOpenAI.id)

            XCTAssertEqual(
                store.accounts.map(\.id),
                [secondOpenAI.id, firstClaude.id, secondClaude.id]
            )
            XCTAssertEqual(
                store.accounts.map { store.accountOrdinal(for: $0.id) },
                [1, 2, 3]
            )
            XCTAssertEqual(
                store.accounts.map { store.accountLabel(for: $0.id) },
                ["OpenAI account 1", "Claude account 2", "Claude account 3"]
            )
            XCTAssertEqual(store.selectedAccountID, secondOpenAI.id)
        }
    }

    func testRemovingSelectedAccountFallsBackWithinProviderAndCompactsOrdinals() throws {
        try withIsolatedDefaults { defaults in
            let store = UsageStore(defaults: defaults, migrateCredentials: false)
            let firstClaude = store.accounts[0]
            let firstOpenAI = store.accounts[1]
            let selectedClaude = store.addAccount(provider: .anthropic)
            let lastOpenAI = store.addAccount(provider: .openAI)
            store.selectedAccountID = selectedClaude.id

            try store.removeAccount(selectedClaude.id)

            XCTAssertEqual(store.selectedAccountID, firstClaude.id)
            XCTAssertEqual(
                store.accounts.map(\.id),
                [firstClaude.id, firstOpenAI.id, lastOpenAI.id]
            )
            XCTAssertEqual(
                store.accounts.map { store.accountLabel(for: $0.id) },
                ["Claude account 1", "OpenAI account 2", "OpenAI account 3"]
            )
            XCTAssertEqual(store.accountOrdinal(for: selectedClaude.id), nil)
            XCTAssertEqual(store.accountLabel(for: selectedClaude.id), "Account")
        }
    }

    func testReorderFirstAccountToLastSlot() {
        withIsolatedDefaults { defaults in
            let store = UsageStore(defaults: defaults, migrateCredentials: false)
            let first = store.accounts[0]
            let second = store.accounts[1]
            let last = store.addAccount(provider: .anthropic)

            store.reorderAccount(first.id, toSlotOf: last.id)

            XCTAssertEqual(store.accounts.map(\.id), [second.id, last.id, first.id])
            XCTAssertEqual(store.accountOrdinal(for: first.id), 3)
            XCTAssertEqual(store.accountLabel(for: first.id), "Claude account 3")
        }
    }

    func testAccountOrderAndSelectionPersistWhileLabelsRemainDerived() {
        withIsolatedDefaults { defaults in
            let store = UsageStore(defaults: defaults, migrateCredentials: false)
            let originalIDs = store.accounts.map(\.id)
            let added = store.addAccount(provider: .openAI)
            store.reorderAccount(added.id, toSlotOf: originalIDs[0])

            let expectedOrder = [added.id, originalIDs[0], originalIDs[1]]
            XCTAssertEqual(store.accounts.map(\.id), expectedOrder)
            XCTAssertEqual(store.selectedAccountID, added.id)

            let reloaded = UsageStore(defaults: defaults, migrateCredentials: false)
            XCTAssertEqual(reloaded.accounts.map(\.id), expectedOrder)
            XCTAssertEqual(reloaded.selectedAccountID, added.id)
            XCTAssertEqual(reloaded.accountLabel(for: added.id), "OpenAI account 1")
            XCTAssertEqual(reloaded.accounts(for: .openAI).count, 2)
        }
    }

    func testShowsAccountNumbersDefaultsOnAndPersistsBothStates() {
        withIsolatedDefaults { defaults in
            let initial = UsageStore(defaults: defaults, migrateCredentials: false)
            XCTAssertTrue(initial.showsAccountNumbers)
            XCTAssertEqual(defaults.object(forKey: "showsAccountNumbers") as? Bool, true)

            initial.showsAccountNumbers = false
            let hidden = UsageStore(defaults: defaults, migrateCredentials: false)
            XCTAssertFalse(hidden.showsAccountNumbers)

            hidden.showsAccountNumbers = true
            let shown = UsageStore(defaults: defaults, migrateCredentials: false)
            XCTAssertTrue(shown.showsAccountNumbers)
        }
    }

    func testLegacyNamedProfilesPreserveIdentityAndScrubCustomLabels() throws {
        try withIsolatedDefaults { defaults in
            let openAIID = UUID()
            let claudeID = UUID()
            let legacyProfiles: [[String: String]] = [
                [
                    "id": openAIID.uuidString,
                    "provider": AIProvider.openAI.rawValue,
                    "name": "personal@example.com",
                ],
                [
                    "id": claudeID.uuidString,
                    "provider": AIProvider.anthropic.rawValue,
                    "name": "Work Claude",
                ],
            ]
            defaults.set(try JSONSerialization.data(withJSONObject: legacyProfiles), forKey: "providerAccounts")
            defaults.set(claudeID.uuidString, forKey: "selectedAccountID")

            let store = UsageStore(defaults: defaults, migrateCredentials: false)

            XCTAssertEqual(store.accounts.map(\.id), [openAIID, claudeID])
            XCTAssertEqual(store.accounts.map(\.provider), [.openAI, .anthropic])
            XCTAssertEqual(store.selectedAccountID, claudeID)
            XCTAssertEqual(
                store.accounts.map { store.accountLabel(for: $0.id) },
                ["OpenAI account 1", "Claude account 2"]
            )

            let migratedData = try XCTUnwrap(defaults.data(forKey: "providerAccounts"))
            let migratedProfiles = try XCTUnwrap(
                JSONSerialization.jsonObject(with: migratedData) as? [[String: Any]]
            )
            XCTAssertEqual(migratedProfiles.map { $0["id"] as? String }, [
                openAIID.uuidString,
                claudeID.uuidString,
            ])
            XCTAssertEqual(migratedProfiles.map { $0["provider"] as? String }, [
                AIProvider.openAI.rawValue,
                AIProvider.anthropic.rawValue,
            ])
            XCTAssertEqual(migratedProfiles.map { $0["name"] as? String }, ["OpenAI", "Claude"])
        }
    }

    func testLegacyCustomNameDoesNotAffectAccountEquality() throws {
        let id = UUID()
        let first = try decodeLegacyAccount(id: id, provider: .openAI, name: "Personal")
        let second = try decodeLegacyAccount(id: id, provider: .openAI, name: "Work")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, ProviderAccount(id: id, provider: .openAI))
    }

    func testProviderAccountRoundTripKeepsIdentityAndWritesGenericLegacyName() throws {
        let account = ProviderAccount(id: UUID(), provider: .openAI)

        let data = try JSONEncoder().encode(account)
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(encoded["id"] as? String, account.id.uuidString)
        XCTAssertEqual(encoded["provider"] as? String, AIProvider.openAI.rawValue)
        XCTAssertEqual(encoded["name"] as? String, "OpenAI")

        let decoded = try JSONDecoder().decode(ProviderAccount.self, from: data)
        XCTAssertEqual(decoded.id, account.id)
        XCTAssertEqual(decoded.provider, account.provider)
        XCTAssertEqual(decoded, account)
    }

    func testSavedProfilesAppendMissingProviderLast() throws {
        try withIsolatedDefaults { defaults in
            let openAI = ProviderAccount(id: UUID(), provider: .openAI)
            defaults.set(try JSONEncoder().encode([openAI]), forKey: "providerAccounts")
            defaults.set(openAI.id.uuidString, forKey: "selectedAccountID")

            let store = UsageStore(defaults: defaults, migrateCredentials: false)

            XCTAssertEqual(store.accounts.count, 2)
            XCTAssertEqual(store.accounts[0], openAI)
            XCTAssertEqual(store.accounts[1].provider, .anthropic)
            XCTAssertEqual(store.accountLabel(for: store.accounts[0]), "OpenAI account 1")
            XCTAssertEqual(store.accountLabel(for: store.accounts[1]), "Claude account 2")
            XCTAssertEqual(store.selectedAccountID, openAI.id)
        }
    }

    func testLegacyProviderOrderAndSelectionSeedInitialAccounts() {
        withIsolatedDefaults { defaults in
            defaults.set(
                [AIProvider.openAI.rawValue, AIProvider.anthropic.rawValue],
                forKey: "providerOrder"
            )
            defaults.set(AIProvider.openAI.rawValue, forKey: "selectedProvider")

            let store = UsageStore(defaults: defaults, migrateCredentials: false)

            XCTAssertEqual(store.accounts.map(\.provider), [.openAI, .anthropic])
            XCTAssertEqual(store.selectedProvider, .openAI)
            XCTAssertEqual(store.accountLabel(for: store.accounts[0]), "OpenAI account 1")
            XCTAssertEqual(store.accountLabel(for: store.accounts[1]), "Claude account 2")
        }
    }

    private func withIsolatedDefaults(
        _ body: (UserDefaults) throws -> Void
    ) rethrows {
        let suiteName = "MultiAccountStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private func decodeLegacyAccount(
        id: UUID,
        provider: AIProvider,
        name: String
    ) throws -> ProviderAccount {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id.uuidString,
            "provider": provider.rawValue,
            "name": name,
        ])
        return try JSONDecoder().decode(ProviderAccount.self, from: data)
    }
}
