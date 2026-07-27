import AppKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsPane: String, CaseIterable, Identifiable, Equatable {
    case general
    case claude
    case openAI
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .claude: return "Claude"
        case .openAI: return "OpenAI"
        case .updates: return "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .claude: return "sparkle"
        case .openAI: return "brain"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }

    var provider: AIProvider? {
        switch self {
        case .claude: return .anthropic
        case .openAI: return .openAI
        case .general, .updates: return nil
        }
    }
}

private struct SettingsStatus {
    enum Kind: Equatable {
        case information
        case success
        case error
    }

    let message: String
    let kind: Kind
}

struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    @EnvironmentObject private var updates: UpdateController

    @State private var selectedPane = SettingsPane.general
    @State private var selectedClaudeAccountID: UUID?
    @State private var selectedOpenAIAccountID: UUID?
    @State private var claudeAccountName = ""
    @State private var openAIAccountName = ""
    @State private var organizationID = ""
    @State private var claudeSessionKey = ""
    @State private var claudeOAuthAccessToken = ""
    @State private var claudeOAuthRefreshToken = ""
    @State private var claudeOAuthExpiresAt: Date?
    @State private var claudeOAuthScopes: [String] = []
    @State private var claudeOAuthRateLimitTier: String?
    @State private var claudeOAuthSubscriptionType: String?

    @State private var openAIAccessToken = ""
    @State private var openAIRefreshToken = ""
    @State private var openAIIDToken = ""
    @State private var openAIAccountID = ""
    @State private var openAILastRefresh: Date?

    @State private var statuses: [UUID: SettingsStatus] = [:]
    @State private var testingAccounts: Set<UUID> = []
    @State private var dirtyAccounts: Set<UUID> = []
    @State private var didLoadCredentials = false
    @State private var savedClaudeAccountName = ""
    @State private var savedOpenAIAccountName = ""
    @State private var savedClaudeCredentials = ClaudeCredentials()
    @State private var savedOpenAICredentials = OpenAICredentials(
        accessToken: "",
        refreshToken: "",
        idToken: "",
        accountID: "",
        lastRefresh: nil
    )
    @State private var accountToDisconnect: UUID?
    @State private var accountToRemove: UUID?
    @State private var dropTargetAccount: UUID?

    /// One accent everywhere — the Volt magenta — including Updates.
    private var paneTint: Color { VoltTheme.primary }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            paneContent
        }
        .frame(width: 700, height: 560)
        .tint(paneTint)
        .onAppear(perform: loadCredentials)
        .onChange(of: draftClaudeCredentials) { _, credentials in
            updateDirtyState(
                selectedClaudeAccountID,
                isDirty: credentials != savedClaudeCredentials
                    || normalizedName(claudeAccountName) != savedClaudeAccountName
            )
        }
        .onChange(of: draftOpenAICredentials) { _, credentials in
            updateDirtyState(
                selectedOpenAIAccountID,
                isDirty: credentials != savedOpenAICredentials
                    || normalizedName(openAIAccountName) != savedOpenAIAccountName
            )
        }
        .onChange(of: claudeAccountName) { _, name in
            updateDirtyState(
                selectedClaudeAccountID,
                isDirty: draftClaudeCredentials != savedClaudeCredentials
                    || normalizedName(name) != savedClaudeAccountName
            )
        }
        .onChange(of: openAIAccountName) { _, name in
            updateDirtyState(
                selectedOpenAIAccountID,
                isDirty: draftOpenAICredentials != savedOpenAICredentials
                    || normalizedName(name) != savedOpenAIAccountName
            )
        }
        .onChange(of: selectedClaudeAccountID) {
            loadClaudeCredentials()
        }
        .onChange(of: selectedOpenAIAccountID) {
            loadOpenAICredentials()
        }
        .confirmationDialog(
            "Disconnect \(accountToDisconnect.flatMap(store.account(for:))?.displayName ?? "account")?",
            isPresented: Binding(
                get: { accountToDisconnect != nil },
                set: { if !$0 { accountToDisconnect = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                disconnectSelectedProvider()
            }
            Button("Cancel", role: .cancel) {
                accountToDisconnect = nil
            }
        } message: {
            Text("Volt will remove this account's saved credentials and cached usage.")
        }
        .confirmationDialog(
            "Remove \(accountToRemove.flatMap(store.account(for:))?.displayName ?? "account")?",
            isPresented: Binding(
                get: { accountToRemove != nil },
                set: { if !$0 { accountToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Account", role: .destructive) {
                removeSelectedAccount()
            }
            Button("Cancel", role: .cancel) {
                accountToRemove = nil
            }
        } message: {
            Text("Volt will remove this tab, its credentials, and its cached usage.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                VoltLogoView(size: 18)
                Text("Volt")
                    .voltHeaderTitle()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    sidebarButton(pane)
                }
            }

            Spacer()
        }
        .frame(width: 190)
        .background(.ultraThinMaterial)
    }

    private func sidebarButton(_ pane: SettingsPane) -> some View {
        let isSelected = selectedPane == pane

        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                selectedPane = pane
            }
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let provider = pane.provider {
                        Image(provider.logoAsset)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                    } else {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 15, height: 15)
                    }
                }
                .foregroundStyle(isSelected ? VoltTheme.primary : Color.secondary)

                Text(pane.title)
                    .voltTabLabel(selected: isSelected)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                isSelected ? VoltTheme.cardHover : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    // MARK: Pane routing

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .general:
            generalPane
        case .claude:
            providerPage(
                provider: .anthropic,
                title: "Claude",
                subtitle: "Connect Claude Code and optionally retain a browser-session fallback"
            ) {
                claudeConnectionContent
            } save: {
                saveClaudeAndTest()
            }
        case .openAI:
            providerPage(
                provider: .openAI,
                title: "OpenAI",
                subtitle: "Connect the ChatGPT account used by Codex"
            ) {
                openAIConnectionContent
            } save: {
                saveOpenAIAndTest()
            }
        case .updates:
            updatesPane
        }
    }

    private var generalPane: some View {
        settingsPage(title: "General", subtitle: "Dashboard behavior and local data handling") {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Dashboard order", detail: "Drag to set the order account tabs appear in the menu.")
                VStack(spacing: 8) {
                    ForEach(store.accounts) { account in
                        accountOrderRow(account)
                    }
                }
            }
            .voltCard()

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Privacy", detail: "Your provider data stays between this Mac and the provider.")
                securityRow("Encrypted credential storage", detail: "Secrets are stored in your macOS login Keychain.", symbol: "key.fill")
                securityRow("Direct provider requests", detail: "Usage requests go directly to Anthropic and OpenAI.", symbol: "arrow.left.arrow.right")
                securityRow("No credential telemetry", detail: "Volt does not proxy, log, or upload credentials.", symbol: "eye.slash.fill")
            }
            .voltCard()
        }
    }

    private var updatesPane: some View {
        settingsPage(title: "Updates", subtitle: "Stay compatible as provider APIs and usage fields evolve") {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Software updates", detail: "Volt checks securely through Sparkle.")

                Toggle(isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.automaticallyChecksForUpdates = $0 }
                )) {
                    Text("Automatically check for updates")
                        .voltControlLabel()
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Installed version")
                            .voltControlLabel()
                        Text(appVersion)
                            .voltDetailValue()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check for Updates…") {
                        updates.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!updates.canCheckForUpdates)
                }
            }
            .voltCard()
        }
    }

    // MARK: Provider pages

    private var claudeConnectionContent: some View {
        Group {
            importCard(
                provider: .anthropic,
                title: "Claude Code",
                detail: "Import the OAuth credentials created by `claude login`. This is the most reliable route and avoids browser-session challenges.",
                buttonTitle: "Import .credentials.json",
                isReady: !claudeOAuthAccessToken.isEmpty,
                action: importClaudeCredentials
            )

            VStack(alignment: .leading, spacing: 0) {
                DisclosureGroup {
                    VStack(spacing: 10) {
                        SecretInput(title: "Access token", text: $claudeOAuthAccessToken)
                        SecretInput(title: "Refresh token", text: $claudeOAuthRefreshToken)
                    }
                    .padding(.top, 12)
                } label: {
                    advancedLabel("Manual OAuth fields", detail: "For advanced setup and troubleshooting")
                }
            }
            .voltCard()

            VStack(alignment: .leading, spacing: 0) {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Organization ID", text: $organizationID)
                            .textFieldStyle(.roundedBorder)
                        SecretInput(title: "Session key", text: $claudeSessionKey)
                        Text("Use the organization UUID and `sessionKey` cookie from a signed-in claude.ai session. Browser sessions can expire or be challenged by Cloudflare.")
                            .voltCaption()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 12)
                } label: {
                    advancedLabel("Browser session fallback", detail: "Optional access to credits and account details")
                }
            }
            .voltCard()
        }
    }

    private var openAIConnectionContent: some View {
        Group {
            importCard(
                provider: .openAI,
                title: "Codex authentication",
                detail: "Run `codex login`, then import ~/.codex/auth.json. Volt keeps an encrypted copy so the access token can refresh automatically.",
                buttonTitle: "Import auth.json",
                isReady: !openAIAccessToken.isEmpty,
                action: importCodexCredentials
            )

            VStack(alignment: .leading, spacing: 0) {
                DisclosureGroup {
                    VStack(spacing: 10) {
                        SecretInput(title: "Access token", text: $openAIAccessToken)
                        SecretInput(title: "Refresh token", text: $openAIRefreshToken)
                        SecretInput(title: "ID token", text: $openAIIDToken)
                        TextField("ChatGPT account ID (optional)", text: $openAIAccountID)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 12)
                } label: {
                    advancedLabel("Manual OAuth fields", detail: "For advanced setup and troubleshooting")
                }
            }
            .voltCard()

            Label(
                "Codex plan limits use ChatGPT's authenticated usage endpoint. It is not a public API and may change.",
                systemImage: "info.circle.fill"
            )
            .voltCaption()
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
        }
    }

    private func providerPage<Content: View>(
        provider: AIProvider,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content,
        save: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            pageHeader(title: title, subtitle: subtitle)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    accountManagementCard(for: provider)
                    if let account = selectedAccount(for: provider) {
                        connectionStatusCard(for: account)
                    }
                    content()
                    if let account = selectedAccount(for: provider) {
                        statusBanner(for: account)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if let account = selectedAccount(for: provider) {
                actionFooter(for: account, save: save)
            }
        }
    }

    private func settingsPage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            pageHeader(title: title, subtitle: subtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .voltTitle()
            Text(subtitle)
                .voltCaption()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: Provider page pieces

    private func accountManagementCard(for provider: AIProvider) -> some View {
        let providerAccounts = store.accounts(for: provider)
        let selection = accountSelectionBinding(for: provider)
        let isDirty = dirtyAccounts.contains(selection.wrappedValue)
        let isBusy = isDirty || testingAccounts.contains(selection.wrappedValue)

        return VStack(alignment: .leading, spacing: 11) {
            SectionHeader("Account tab", detail: "Each account appears as its own tab in the Volt drawer.")

            HStack(spacing: 8) {
                Picker("Account", selection: selection) {
                    ForEach(providerAccounts) { account in
                        Text(account.displayName).tag(account.id)
                    }
                }
                .labelsHidden()
                .disabled(isBusy)

                Button {
                    addAccount(provider)
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
                .disabled(isBusy)
            }

            TextField("Tab name", text: accountNameBinding(for: provider))
                .textFieldStyle(.roundedBorder)

            if isDirty {
                HStack {
                    Text("Save or discard changes before switching accounts.")
                        .voltCaption()
                    Spacer()
                    Button("Discard Changes") {
                        discardChanges(for: provider)
                    }
                }
            }
        }
        .voltCard()
    }

    private func connectionStatusCard(for account: ProviderAccount) -> some View {
        let provider = account.provider
        return HStack(spacing: 12) {
            VoltLogoGlyph(asset: provider.logoAsset, tint: provider.tint, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(connectionTitle(for: account))
                    .voltControlLabel()
                    .foregroundStyle(connectionColor(for: account))
                Text(connectionDetail(for: account))
                    .voltCaption()
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
        .voltCard()
    }

    private func importCard(
        provider: AIProvider,
        title: String,
        detail: String,
        buttonTitle: String,
        isReady: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: "terminal.fill")
                    .voltControlLabel()
                Spacer()
                statusChip(title: "Recommended", color: VoltTheme.primary, symbol: "star.fill")
            }

            Text(detail)
                .voltCaption()
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: action) {
                    Label(buttonTitle, systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(VoltTheme.primary)

                if isReady {
                    statusChip(title: "Credential ready", color: VoltTheme.primary, symbol: "checkmark")
                }
            }
        }
        .voltCard()
    }

    private func advancedLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .voltControlLabel()
            Text(detail)
                .voltCaption()
        }
    }

    private func accountOrderRow(_ account: ProviderAccount) -> some View {
        let provider = account.provider
        let isDropTarget = dropTargetAccount == account.id

        return HStack(spacing: 11) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VoltLogoGlyph(asset: provider.logoAsset, tint: provider.tint, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.displayName)
                    .voltControlLabel()
                Text(provider.companyName)
                    .voltCaption()
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(VoltTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTarget ? VoltTheme.primary.opacity(0.65) : VoltTheme.hairline,
                    lineWidth: isDropTarget ? 1 : 0.5
                )
        }
        .contentShape(Rectangle())
        .draggable(account.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            dropTargetAccount = nil
            guard let rawID = items.first, let draggedID = UUID(uuidString: rawID) else { return false }
            withAnimation(.easeOut(duration: 0.18)) {
                store.reorderAccount(draggedID, toSlotOf: account.id)
            }
            return true
        } isTargeted: { targeted in
            dropTargetAccount = targeted ? account.id : (dropTargetAccount == account.id ? nil : dropTargetAccount)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.displayName), drag to reorder")
    }

    private func securityRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .voltControlLabel()
                Text(detail)
                    .voltCaption()
            }
            Spacer(minLength: 0)
        }
    }

    private func statusChip(title: String, color: Color, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .lineLimit(1)
        }
        .voltChipText()
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func statusBanner(for account: ProviderAccount) -> some View {
        if let status = statuses[account.id],
           !(dirtyAccounts.contains(account.id) && status.kind == .success) {
            let symbol: String = switch status.kind {
            case .information: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
            let color: Color = switch status.kind {
            case .information: VoltTheme.primary
            case .success: VoltTheme.primary
            case .error: .orange
            }

            Label(status.message, systemImage: symbol)
                .voltChipText()
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func actionFooter(for account: ProviderAccount, save: @escaping () -> Void) -> some View {
        let accountID = account.id
        return HStack {
            Button("Disconnect…", role: .destructive) {
                accountToDisconnect = accountID
            }
            .disabled(
                (!store.isConfigured(accountID) && statuses[accountID]?.kind != .error)
                    || testingAccounts.contains(accountID)
            )

            if store.accounts(for: account.provider).count > 1 {
                Button("Remove Account…", role: .destructive) {
                    accountToRemove = accountID
                }
                .disabled(testingAccounts.contains(accountID))
            }

            Spacer()

            if dirtyAccounts.contains(accountID) {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .voltChipText()
                    .foregroundStyle(VoltTheme.primary)
            }

            Button(action: save) {
                HStack(spacing: 7) {
                    if testingAccounts.contains(accountID) {
                        ProgressView().controlSize(.small)
                    }
                    Text(testingAccounts.contains(accountID) ? "Testing…" : "Save & Test")
                }
                .frame(minWidth: 78)
            }
            .buttonStyle(.borderedProminent)
            .tint(VoltTheme.primary)
            .disabled(store.isLoading(accountID) || testingAccounts.contains(accountID))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: Connection copy helpers

    private func connectionTitle(for account: ProviderAccount) -> String {
        if testingAccounts.contains(account.id) || store.isLoading(account.id) { return "Testing connection…" }
        if dirtyAccounts.contains(account.id) { return "Unsaved changes" }
        if store.snapshot(for: account.id) != nil, store.error(for: account.id) == nil { return "Connected" }
        if store.isConfigured(account.id) { return "Credentials saved" }
        return "Not connected"
    }

    private func connectionDetail(for account: ProviderAccount) -> String {
        if dirtyAccounts.contains(account.id) {
            return "Save and test these changes before Volt uses them."
        }
        if let snapshot = store.snapshot(for: account.id), let subtitle = snapshot.subtitle {
            return subtitle
        }
        if let error = store.error(for: account.id) {
            return error
        }
        return store.isConfigured(account.id)
            ? "Save & Test to verify the current credentials"
            : "Import credentials below to connect this provider"
    }

    private func connectionColor(for account: ProviderAccount) -> Color {
        if store.error(for: account.id) != nil { return .orange }
        if store.snapshot(for: account.id) != nil { return VoltTheme.primary }
        if store.isConfigured(account.id)
            || dirtyAccounts.contains(account.id)
            || testingAccounts.contains(account.id) {
            return VoltTheme.primary
        }
        return .secondary
    }

    // MARK: Credential state

    private var draftClaudeCredentials: ClaudeCredentials {
        normalizedClaude(ClaudeCredentials(
            organizationID: organizationID,
            sessionKey: claudeSessionKey,
            oauthAccessToken: claudeOAuthAccessToken,
            oauthRefreshToken: claudeOAuthRefreshToken,
            oauthExpiresAt: claudeOAuthExpiresAt,
            oauthScopes: claudeOAuthScopes,
            oauthRateLimitTier: claudeOAuthRateLimitTier,
            oauthSubscriptionType: claudeOAuthSubscriptionType
        ))
    }

    private var draftOpenAICredentials: OpenAICredentials {
        normalizedOpenAI(OpenAICredentials(
            accessToken: openAIAccessToken,
            refreshToken: openAIRefreshToken,
            idToken: openAIIDToken,
            accountID: openAIAccountID,
            lastRefresh: openAILastRefresh
        ))
    }

    /// The canonical form used for *both* the live draft and the saved baseline,
    /// so a freshly loaded credential set is never mistaken for an edit. Because
    /// both sides pass through the same normalization (`canonical`), dirty state
    /// is true only when the user actually changes a value.
    private func normalizedClaude(_ c: ClaudeCredentials) -> ClaudeCredentials { c.canonical }

    private func normalizedOpenAI(_ c: OpenAICredentials) -> OpenAICredentials { c.canonical }

    private var appVersion: String {
        "\(bundleValue("CFBundleShortVersionString")) (\(bundleValue("CFBundleVersion")))"
    }

    private func bundleValue(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return "—"
        }
        return value
    }

    private func loadCredentials() {
        didLoadCredentials = false
        let dashboardAccount = store.selectedAccount
        selectedPane = dashboardAccount.provider == .anthropic ? .claude : .openAI
        selectedClaudeAccountID = dashboardAccount.provider == .anthropic
            ? dashboardAccount.id
            : (selectedClaudeAccountID ?? store.accounts(for: .anthropic).first?.id)
        selectedOpenAIAccountID = dashboardAccount.provider == .openAI
            ? dashboardAccount.id
            : (selectedOpenAIAccountID ?? store.accounts(for: .openAI).first?.id)
        loadClaudeCredentials()
        loadOpenAICredentials()
        dirtyAccounts.removeAll()
        didLoadCredentials = true
    }

    private func loadClaudeCredentials() {
        guard let accountID = selectedClaudeAccountID,
              let account = store.account(for: accountID)
        else { return }
        let wasLoaded = didLoadCredentials
        didLoadCredentials = false
        defer { didLoadCredentials = wasLoaded }
        claudeAccountName = account.displayName
        savedClaudeAccountName = account.displayName
        do {
            let credentials = try store.claudeCredentials(accountID: accountID)
            applyClaudeCredentials(credentials)
            savedClaudeCredentials = normalizedClaude(credentials)
            dirtyAccounts.remove(accountID)
        } catch {
            statuses[accountID] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func loadOpenAICredentials() {
        guard let accountID = selectedOpenAIAccountID,
              let account = store.account(for: accountID)
        else { return }
        let wasLoaded = didLoadCredentials
        didLoadCredentials = false
        defer { didLoadCredentials = wasLoaded }
        openAIAccountName = account.displayName
        savedOpenAIAccountName = account.displayName
        do {
            let credentials = try store.openAICredentials(accountID: accountID)
            applyOpenAICredentials(credentials)
            savedOpenAICredentials = normalizedOpenAI(credentials)
            dirtyAccounts.remove(accountID)
        } catch {
            statuses[accountID] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func saveClaudeAndTest() {
        guard let accountID = selectedClaudeAccountID else { return }
        let credentials = draftClaudeCredentials
        guard credentials.isComplete else {
            statuses[accountID] = SettingsStatus(
                message: "Import Claude Code credentials or complete both browser-session fields.",
                kind: .error
            )
            return
        }

        do {
            store.renameAccount(accountID, to: claudeAccountName)
            try store.saveClaude(credentials, accountID: accountID)
            savedClaudeCredentials = credentials
            savedClaudeAccountName = store.account(for: accountID)?.displayName
                ?? normalizedName(claudeAccountName)
            claudeAccountName = savedClaudeAccountName
            let savedName = savedClaudeAccountName
            dirtyAccounts.remove(accountID)
            testingAccounts.insert(accountID)
            statuses[accountID] = SettingsStatus(
                message: "Credentials saved. Testing the connection…",
                kind: .information
            )
            Task {
                let succeeded = await store.refresh(accountID)
                testingAccounts.remove(accountID)
                if succeeded, store.snapshot(for: accountID) != nil {
                    if let refreshed = try? store.claudeCredentials(accountID: accountID) {
                        let draftWasUnchanged = draftClaudeCredentials == credentials
                            && normalizedName(claudeAccountName) == savedName
                        savedClaudeCredentials = normalizedClaude(refreshed)
                        if draftWasUnchanged, selectedClaudeAccountID == accountID {
                            applyClaudeCredentials(refreshed)
                            dirtyAccounts.remove(accountID)
                        } else {
                            dirtyAccounts.insert(accountID)
                        }
                    }
                    statuses[accountID] = SettingsStatus(
                        message: "Claude connected successfully.",
                        kind: .success
                    )
                } else if let error = store.error(for: accountID) {
                    statuses[accountID] = SettingsStatus(message: error, kind: .error)
                } else {
                    statuses[accountID] = SettingsStatus(
                        message: "The connection test did not complete. Try again.",
                        kind: .error
                    )
                }
            }
        } catch {
            statuses[accountID] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func saveOpenAIAndTest() {
        guard let accountID = selectedOpenAIAccountID else { return }
        let credentials = draftOpenAICredentials
        guard credentials.isComplete else {
            statuses[accountID] = SettingsStatus(
                message: "Import Codex auth.json or enter an OAuth access token.",
                kind: .error
            )
            return
        }

        do {
            store.renameAccount(accountID, to: openAIAccountName)
            try store.saveOpenAI(credentials, accountID: accountID)
            savedOpenAICredentials = credentials
            savedOpenAIAccountName = store.account(for: accountID)?.displayName
                ?? normalizedName(openAIAccountName)
            openAIAccountName = savedOpenAIAccountName
            let savedName = savedOpenAIAccountName
            dirtyAccounts.remove(accountID)
            testingAccounts.insert(accountID)
            statuses[accountID] = SettingsStatus(
                message: "Credentials saved. Testing the connection…",
                kind: .information
            )
            Task {
                let succeeded = await store.refresh(accountID)
                testingAccounts.remove(accountID)
                if succeeded, store.snapshot(for: accountID) != nil {
                    if let refreshed = try? store.openAICredentials(accountID: accountID) {
                        let draftWasUnchanged = draftOpenAICredentials == credentials
                            && normalizedName(openAIAccountName) == savedName
                        savedOpenAICredentials = normalizedOpenAI(refreshed)
                        if draftWasUnchanged, selectedOpenAIAccountID == accountID {
                            applyOpenAICredentials(refreshed)
                            dirtyAccounts.remove(accountID)
                        } else {
                            dirtyAccounts.insert(accountID)
                        }
                    }
                    statuses[accountID] = SettingsStatus(
                        message: "OpenAI connected successfully.",
                        kind: .success
                    )
                } else if let error = store.error(for: accountID) {
                    statuses[accountID] = SettingsStatus(message: error, kind: .error)
                } else {
                    statuses[accountID] = SettingsStatus(
                        message: "The connection test did not complete. Try again.",
                        kind: .error
                    )
                }
            }
        } catch {
            statuses[accountID] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func importClaudeCredentials() {
        guard let accountID = selectedClaudeAccountID else { return }
        let panel = credentialPanel(
            title: "Choose Claude Code .credentials.json",
            defaultDirectory: ".claude",
            fileName: ".credentials.json"
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let imported = try ClaudeCredentials.imported(from: Data(contentsOf: url))
            claudeOAuthAccessToken = imported.oauthAccessToken ?? ""
            claudeOAuthRefreshToken = imported.oauthRefreshToken ?? ""
            claudeOAuthExpiresAt = imported.oauthExpiresAt
            claudeOAuthScopes = imported.oauthScopes ?? []
            claudeOAuthRateLimitTier = imported.oauthRateLimitTier
            claudeOAuthSubscriptionType = imported.oauthSubscriptionType
            statuses[accountID] = SettingsStatus(
                message: "Imported Claude Code credentials. Select Save & Test to connect.",
                kind: .information
            )
        } catch {
            statuses[accountID] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func importCodexCredentials() {
        guard let accountID = selectedOpenAIAccountID else { return }
        let panel = credentialPanel(
            title: "Choose Codex auth.json",
            defaultDirectory: ".codex",
            fileName: "auth.json"
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let credentials = try OpenAICredentials.imported(from: Data(contentsOf: url))
            openAIAccessToken = credentials.accessToken
            openAIRefreshToken = credentials.refreshToken
            openAIIDToken = credentials.idToken
            openAIAccountID = credentials.accountID
            openAILastRefresh = credentials.lastRefresh
            if openAIAccountName.hasPrefix("OpenAI"), let email = credentials.accountEmail {
                openAIAccountName = email
            }
            statuses[accountID] = SettingsStatus(
                message: "Imported Codex credentials. Select Save & Test to connect.",
                kind: .information
            )
        } catch {
            statuses[accountID] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func credentialPanel(title: String, defaultDirectory: String, fileName: String) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true

        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(defaultDirectory, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            panel.directoryURL = directory
        }
        panel.nameFieldStringValue = fileName
        return panel
    }

    private func applyClaudeCredentials(_ credentials: ClaudeCredentials) {
        organizationID = credentials.organizationID
        claudeSessionKey = credentials.sessionKey
        claudeOAuthAccessToken = credentials.oauthAccessToken ?? ""
        claudeOAuthRefreshToken = credentials.oauthRefreshToken ?? ""
        claudeOAuthExpiresAt = credentials.oauthExpiresAt
        claudeOAuthScopes = credentials.oauthScopes ?? []
        claudeOAuthRateLimitTier = credentials.oauthRateLimitTier
        claudeOAuthSubscriptionType = credentials.oauthSubscriptionType
    }

    private func applyOpenAICredentials(_ credentials: OpenAICredentials) {
        openAIAccessToken = credentials.accessToken
        openAIRefreshToken = credentials.refreshToken
        openAIIDToken = credentials.idToken
        openAIAccountID = credentials.accountID
        openAILastRefresh = credentials.lastRefresh
    }

    private func updateDirtyState(_ accountID: UUID?, isDirty: Bool) {
        guard didLoadCredentials, let accountID else { return }
        if isDirty {
            dirtyAccounts.insert(accountID)
            if statuses[accountID]?.kind != .information {
                statuses.removeValue(forKey: accountID)
            }
        } else {
            dirtyAccounts.remove(accountID)
        }
    }

    private func disconnectSelectedProvider() {
        guard let accountID = accountToDisconnect,
              let account = store.account(for: accountID)
        else { return }
        defer { accountToDisconnect = nil }
        do {
            try store.disconnect(accountID)
            switch account.provider {
            case .anthropic:
                if selectedClaudeAccountID == accountID {
                    loadClaudeCredentials()
                }
            case .openAI:
                if selectedOpenAIAccountID == accountID {
                    loadOpenAICredentials()
                }
            }
            dirtyAccounts.remove(accountID)
            statuses[accountID] = SettingsStatus(
                message: "\(account.displayName) disconnected.",
                kind: .success
            )
        } catch {
            statuses[accountID] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func addAccount(_ provider: AIProvider) {
        let account = store.addAccount(provider: provider)
        switch provider {
        case .anthropic:
            selectedClaudeAccountID = account.id
        case .openAI:
            selectedOpenAIAccountID = account.id
        }
    }

    private func discardChanges(for provider: AIProvider) {
        switch provider {
        case .anthropic:
            loadClaudeCredentials()
        case .openAI:
            loadOpenAICredentials()
        }
    }

    private func removeSelectedAccount() {
        guard let accountID = accountToRemove,
              let account = store.account(for: accountID)
        else { return }
        defer { accountToRemove = nil }
        do {
            try store.removeAccount(accountID)
            statuses.removeValue(forKey: accountID)
            dirtyAccounts.remove(accountID)
            switch account.provider {
            case .anthropic:
                selectedClaudeAccountID = store.accounts(for: .anthropic).first?.id
            case .openAI:
                selectedOpenAIAccountID = store.accounts(for: .openAI).first?.id
            }
        } catch {
            statuses[accountID] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func selectedAccount(for provider: AIProvider) -> ProviderAccount? {
        let accountID = provider == .anthropic ? selectedClaudeAccountID : selectedOpenAIAccountID
        return accountID.flatMap(store.account(for:))
    }

    private func accountSelectionBinding(for provider: AIProvider) -> Binding<UUID> {
        Binding(
            get: {
                let selected = provider == .anthropic ? selectedClaudeAccountID : selectedOpenAIAccountID
                return selected ?? store.accounts(for: provider)[0].id
            },
            set: { accountID in
                if provider == .anthropic {
                    selectedClaudeAccountID = accountID
                } else {
                    selectedOpenAIAccountID = accountID
                }
            }
        )
    }

    private func accountNameBinding(for provider: AIProvider) -> Binding<String> {
        provider == .anthropic ? $claudeAccountName : $openAIAccountName
    }

    private func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Account" : trimmed
    }
}

private struct SecretInput: View {
    let title: String
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if isRevealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .frame(width: 26, height: 26)
                    .background(VoltTheme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isRevealed ? "Hide credential" : "Show credential")
            .accessibilityLabel(isRevealed ? "Hide \(title)" : "Show \(title)")
        }
    }
}
