import AppKit
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
        case .general: return "gearshape"
        case .claude: return "sparkles"
        case .openAI: return "brain.head.profile"
        case .updates: return "arrow.triangle.2.circlepath"
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

    init(message: String, kind: Kind) {
        self.message = message
        self.kind = kind
    }
}

struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    @EnvironmentObject private var updates: UpdateController

    @State private var selectedPane = SettingsPane.general
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

    @State private var statuses: [AIProvider: SettingsStatus] = [:]
    @State private var testingProviders: Set<AIProvider> = []
    @State private var dirtyProviders: Set<AIProvider> = []
    @State private var didLoadCredentials = false
    @State private var savedClaudeCredentials = ClaudeCredentials()
    @State private var savedOpenAICredentials = OpenAICredentials(
        accessToken: "",
        refreshToken: "",
        idToken: "",
        accountID: "",
        lastRefresh: nil
    )
    @State private var providerToDisconnect: AIProvider?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            paneContent
        }
        .frame(width: 740, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(VoltTheme.primary)
        .onAppear(perform: loadCredentials)
        .onChange(of: draftClaudeCredentials) { _, credentials in
            updateDirtyState(.anthropic, isDirty: credentials != savedClaudeCredentials)
        }
        .onChange(of: draftOpenAICredentials) { _, credentials in
            updateDirtyState(.openAI, isDirty: credentials != savedOpenAICredentials)
        }
        .confirmationDialog(
            "Disconnect \(providerToDisconnect?.displayName ?? "provider")?",
            isPresented: Binding(
                get: { providerToDisconnect != nil },
                set: { if !$0 { providerToDisconnect = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                disconnectSelectedProvider()
            }
            Button("Cancel", role: .cancel) {
                providerToDisconnect = nil
            }
        } message: {
            Text("Volt will remove the saved credentials and cached usage for this provider.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                VoltLogoView(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Volt")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("Settings")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 16)

            VStack(spacing: 3) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        selectedPane = pane
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: pane.symbol)
                                .frame(width: 16)
                            Text(pane.title)
                            Spacer()
                            if pane == .claude || pane == .openAI {
                                let provider: AIProvider = pane == .claude ? .anthropic : .openAI
                                Circle()
                                    .fill(connectionColor(for: provider))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .font(.system(size: 12.5, weight: selectedPane == pane ? .semibold : .regular))
                        .foregroundStyle(selectedPane == pane ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            selectedPane == pane ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            Text("Version \(appVersion)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(14)
        }
        .frame(width: 166)
        .background(Color.primary.opacity(0.025))
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .general:
            generalPane
        case .claude:
            claudePane
        case .openAI:
            openAIPane
        case .updates:
            updatesPane
        }
    }

    private var generalPane: some View {
        settingsPage(title: "General", subtitle: "Choose how Volt opens and handles provider data") {
            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Dashboard", symbol: "rectangle.3.group")
                    LabeledContent("Default provider") {
                        Picker("Default provider", selection: Binding(
                            get: { store.selectedProvider },
                            set: { store.selectedProvider = $0 }
                        )) {
                            ForEach(AIProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    Text("Volt remembers the provider selected in the menu-bar dashboard.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Privacy & security", symbol: "lock.shield")
                    Label("Credentials are encrypted in your macOS login Keychain.", systemImage: "checkmark.shield.fill")
                    Label("Usage requests go directly to Anthropic and OpenAI.", systemImage: "arrow.left.arrow.right")
                    Label("Volt does not proxy, log, or upload provider credentials.", systemImage: "eye.slash")
                }
                .font(.system(size: 11.5))
            }
        }
    }

    private var claudePane: some View {
        settingsPage(
            title: "Claude",
            subtitle: "OAuth is preferred; a browser session can remain as a fallback"
        ) {
            connectionCard(for: .anthropic)

            settingsCard {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        sectionLabel("Claude Code", symbol: "terminal")
                        Spacer()
                        Text("Recommended")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(AIProvider.anthropic.tint)
                    }
                    Text("Import the OAuth credentials created by `claude login`. This route avoids the Cloudflare challenges that can block browser-session requests.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button {
                            importClaudeCredentials()
                        } label: {
                            Label("Import .credentials.json", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AIProvider.anthropic.tint)

                        if !claudeOAuthAccessToken.isEmpty {
                            Label("OAuth credential ready", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    }

                    DisclosureGroup("Manual OAuth fields") {
                        VStack(spacing: 9) {
                            SecretInput(title: "Access token", text: $claudeOAuthAccessToken)
                            SecretInput(title: "Refresh token", text: $claudeOAuthRefreshToken)
                        }
                        .padding(.top, 9)
                    }
                    .font(.system(size: 11.5))
                }
            }

            settingsCard {
                DisclosureGroup("Browser session fallback") {
                    VStack(alignment: .leading, spacing: 9) {
                        TextField("Organization ID", text: $organizationID)
                            .textFieldStyle(.roundedBorder)
                        SecretInput(title: "Session key", text: $claudeSessionKey)
                        Text("Use the organization UUID and `sessionKey` cookie from a signed-in claude.ai session. Browser sessions may expire or be challenged by Cloudflare.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 9)
                }
                .font(.system(size: 11.5, weight: .medium))
            }

            statusBanner(for: .anthropic)
        } actions: {
            providerActions(for: .anthropic) {
                saveClaudeAndTest()
            }
        }
    }

    private var openAIPane: some View {
        settingsPage(
            title: "OpenAI",
            subtitle: "Connect the same ChatGPT account used by Codex"
        ) {
            connectionCard(for: .openAI)

            settingsCard {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        sectionLabel("Codex authentication", symbol: "terminal")
                        Spacer()
                        Text("Recommended")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(AIProvider.openAI.tint)
                    }
                    Text("Run `codex login`, then import ~/.codex/auth.json. Volt stores its own encrypted copy so tokens can refresh automatically.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button {
                            importCodexCredentials()
                        } label: {
                            Label("Import auth.json", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AIProvider.openAI.tint)

                        if !openAIAccessToken.isEmpty {
                            Label("OAuth credential ready", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }

            settingsCard {
                DisclosureGroup("Manual OAuth fields") {
                    VStack(spacing: 9) {
                        SecretInput(title: "Access token", text: $openAIAccessToken)
                        SecretInput(title: "Refresh token", text: $openAIRefreshToken)
                        SecretInput(title: "ID token", text: $openAIIDToken)
                        TextField("ChatGPT account ID (optional)", text: $openAIAccountID)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 9)
                }
                .font(.system(size: 11.5, weight: .medium))
            }

            Text("Codex plan limits come from ChatGPT’s authenticated usage endpoint. It is not a public API and may change.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            statusBanner(for: .openAI)
        } actions: {
            providerActions(for: .openAI) {
                saveOpenAIAndTest()
            }
        }
    }

    private var updatesPane: some View {
        settingsPage(title: "Updates", subtitle: "Keep Volt current with provider and endpoint changes") {
            settingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("Software updates", symbol: "arrow.triangle.2.circlepath")
                    Toggle(
                        "Automatically check for updates",
                        isOn: Binding(
                            get: { updates.automaticallyChecksForUpdates },
                            set: { updates.automaticallyChecksForUpdates = $0 }
                        )
                    )
                    Text("Provider usage endpoints can change without notice. Keeping Volt updated helps maintain compatibility.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("Check for Updates…") {
                            updates.checkForUpdates()
                        }
                        .disabled(!updates.canCheckForUpdates)
                        Spacer()
                        Text("Version \(appVersion)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func settingsPage<Content: View, Actions: View>(
        title: String,
        subtitle: String,
        showsActions: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 19)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if showsActions {
                Divider()
                actions()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
    }

    private func settingsPage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsPage(title: title, subtitle: subtitle, showsActions: false, content: content) {
            EmptyView()
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VoltTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(VoltTheme.hairline, lineWidth: 0.5)
            )
    }

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12.5, weight: .semibold))
    }

    private func connectionCard(for provider: AIProvider) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(provider.tint.opacity(0.12))
                Image(systemName: provider.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(provider.tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(connectionTitle(for: provider))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(connectionDetail(for: provider))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Circle()
                .fill(connectionColor(for: provider))
                .frame(width: 7, height: 7)
        }
        .padding(11)
        .background(provider.tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func statusBanner(for provider: AIProvider) -> some View {
        if let status = statuses[provider],
           !(dirtyProviders.contains(provider) && status.kind == .success) {
            let symbol: String = switch status.kind {
            case .information: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
            let color: Color = switch status.kind {
            case .information: provider.tint
            case .success: .green
            case .error: .orange
            }
            Label(status.message, systemImage: symbol)
                .font(.system(size: 10.5))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func providerActions(for provider: AIProvider, save: @escaping () -> Void) -> some View {
        HStack {
            Button("Disconnect…", role: .destructive) {
                providerToDisconnect = provider
            }
            .disabled(
                (!store.isConfigured(provider) && statuses[provider]?.kind != .error)
                    || testingProviders.contains(provider)
            )

            Spacer()

            Button(action: save) {
                HStack(spacing: 6) {
                    if testingProviders.contains(provider) {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(testingProviders.contains(provider) ? "Testing…" : "Save & Test")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(provider.tint)
            .disabled(store.isLoading(provider) || testingProviders.contains(provider))
        }
    }

    private func connectionTitle(for provider: AIProvider) -> String {
        if testingProviders.contains(provider) || store.isLoading(provider) { return "Testing connection…" }
        if dirtyProviders.contains(provider) { return "Unsaved changes" }
        if store.snapshot(for: provider) != nil, store.error(for: provider) == nil { return "Connected" }
        if store.isConfigured(provider) { return "Credentials saved" }
        return "Not connected"
    }

    private func connectionDetail(for provider: AIProvider) -> String {
        if dirtyProviders.contains(provider) {
            return "Save and test these changes before they are used."
        }
        if let snapshot = store.snapshot(for: provider), let subtitle = snapshot.subtitle {
            return subtitle
        }
        if let error = store.error(for: provider) {
            return error
        }
        return store.isConfigured(provider)
            ? "Save & Test to verify the current credentials"
            : "Add credentials below to connect"
    }

    private func connectionColor(for provider: AIProvider) -> Color {
        if testingProviders.contains(provider) { return provider.tint }
        if dirtyProviders.contains(provider) { return provider.tint }
        if store.snapshot(for: provider) != nil, store.error(for: provider) == nil { return .green }
        if store.error(for: provider) != nil { return .orange }
        return store.isConfigured(provider) ? provider.tint : Color.secondary.opacity(0.4)
    }

    private var draftClaudeCredentials: ClaudeCredentials {
        ClaudeCredentials(
            organizationID: organizationID.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionKey: claudeSessionKey.trimmingCharacters(in: .whitespacesAndNewlines),
            oauthAccessToken: nilIfEmpty(claudeOAuthAccessToken),
            oauthRefreshToken: nilIfEmpty(claudeOAuthRefreshToken),
            oauthExpiresAt: claudeOAuthExpiresAt,
            oauthScopes: claudeOAuthScopes,
            oauthRateLimitTier: claudeOAuthRateLimitTier,
            oauthSubscriptionType: claudeOAuthSubscriptionType
        )
    }

    private var draftOpenAICredentials: OpenAICredentials {
        OpenAICredentials(
            accessToken: openAIAccessToken.trimmingCharacters(in: .whitespacesAndNewlines),
            refreshToken: openAIRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines),
            idToken: openAIIDToken.trimmingCharacters(in: .whitespacesAndNewlines),
            accountID: openAIAccountID.trimmingCharacters(in: .whitespacesAndNewlines),
            lastRefresh: openAILastRefresh
        )
    }

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
        defer { didLoadCredentials = true }

        do {
            let credentials = try store.claudeCredentials()
            applyClaudeCredentials(credentials)
            savedClaudeCredentials = credentials
        } catch {
            statuses[.anthropic] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }

        do {
            let credentials = try store.openAICredentials()
            applyOpenAICredentials(credentials)
            savedOpenAICredentials = credentials
        } catch {
            statuses[.openAI] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }

        dirtyProviders.removeAll()
    }

    private func saveClaudeAndTest() {
        let credentials = draftClaudeCredentials
        guard credentials.isComplete else {
            statuses[.anthropic] = SettingsStatus(
                message: "Import Claude Code credentials or complete both browser-session fields.",
                kind: .error
            )
            return
        }

        do {
            try store.saveClaude(credentials)
            savedClaudeCredentials = credentials
            dirtyProviders.remove(.anthropic)
            testingProviders.insert(.anthropic)
            statuses[.anthropic] = SettingsStatus(
                message: "Credentials saved. Testing the connection…",
                kind: .information
            )
            Task {
                let succeeded = await store.refresh(.anthropic)
                testingProviders.remove(.anthropic)
                if succeeded, store.snapshot(for: .anthropic) != nil {
                    if let refreshed = try? store.claudeCredentials() {
                        let draftWasUnchanged = draftClaudeCredentials == credentials
                        savedClaudeCredentials = refreshed
                        if draftWasUnchanged {
                            applyClaudeCredentials(refreshed)
                            dirtyProviders.remove(.anthropic)
                        } else {
                            dirtyProviders.insert(.anthropic)
                        }
                    }
                    statuses[.anthropic] = SettingsStatus(
                        message: "Claude connected successfully.",
                        kind: .success
                    )
                } else if let error = store.error(for: .anthropic) {
                    statuses[.anthropic] = SettingsStatus(message: error, kind: .error)
                } else {
                    statuses[.anthropic] = SettingsStatus(
                        message: "The connection test did not complete. Try again.",
                        kind: .error
                    )
                }
            }
        } catch {
            statuses[.anthropic] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func saveOpenAIAndTest() {
        let credentials = draftOpenAICredentials
        guard credentials.isComplete else {
            statuses[.openAI] = SettingsStatus(
                message: "Import Codex auth.json or enter an OAuth access token.",
                kind: .error
            )
            return
        }

        do {
            try store.saveOpenAI(credentials)
            savedOpenAICredentials = credentials
            dirtyProviders.remove(.openAI)
            testingProviders.insert(.openAI)
            statuses[.openAI] = SettingsStatus(
                message: "Credentials saved. Testing the connection…",
                kind: .information
            )
            Task {
                let succeeded = await store.refresh(.openAI)
                testingProviders.remove(.openAI)
                if succeeded, store.snapshot(for: .openAI) != nil {
                    if let refreshed = try? store.openAICredentials() {
                        let draftWasUnchanged = draftOpenAICredentials == credentials
                        savedOpenAICredentials = refreshed
                        if draftWasUnchanged {
                            applyOpenAICredentials(refreshed)
                            dirtyProviders.remove(.openAI)
                        } else {
                            dirtyProviders.insert(.openAI)
                        }
                    }
                    statuses[.openAI] = SettingsStatus(
                        message: "OpenAI connected successfully.",
                        kind: .success
                    )
                } else if let error = store.error(for: .openAI) {
                    statuses[.openAI] = SettingsStatus(message: error, kind: .error)
                } else {
                    statuses[.openAI] = SettingsStatus(
                        message: "The connection test did not complete. Try again.",
                        kind: .error
                    )
                }
            }
        } catch {
            statuses[.openAI] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func importClaudeCredentials() {
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
            statuses[.anthropic] = SettingsStatus(
                message: "Imported Claude Code credentials. Select Save & Test to connect.",
                kind: .information
            )
        } catch {
            statuses[.anthropic] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func importCodexCredentials() {
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
            statuses[.openAI] = SettingsStatus(
                message: "Imported Codex credentials. Select Save & Test to connect.",
                kind: .information
            )
        } catch {
            statuses[.openAI] = SettingsStatus(message: error.localizedDescription, kind: .error)
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

    private func updateDirtyState(_ provider: AIProvider, isDirty: Bool) {
        guard didLoadCredentials else { return }
        if isDirty {
            dirtyProviders.insert(provider)
            if statuses[provider]?.kind != .information {
                statuses.removeValue(forKey: provider)
            }
        } else {
            dirtyProviders.remove(provider)
        }
    }

    private func disconnectSelectedProvider() {
        guard let provider = providerToDisconnect else { return }
        defer { providerToDisconnect = nil }
        do {
            try store.disconnect(provider)
            switch provider {
            case .anthropic:
                let empty = ClaudeCredentials()
                applyClaudeCredentials(empty)
                savedClaudeCredentials = empty
            case .openAI:
                let empty = OpenAICredentials(
                    accessToken: "",
                    refreshToken: "",
                    idToken: "",
                    accountID: "",
                    lastRefresh: nil
                )
                applyOpenAICredentials(empty)
                savedOpenAICredentials = empty
            }
            dirtyProviders.remove(provider)
            statuses[provider] = SettingsStatus(
                message: "\(provider.displayName) disconnected.",
                kind: .success
            )
        } catch {
            statuses[provider] = SettingsStatus(message: error.localizedDescription, kind: .error)
        }
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct SecretInput: View {
    let title: String
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 6) {
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
                    .frame(width: 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isRevealed ? "Hide credential" : "Show credential")
            .accessibilityLabel(isRevealed ? "Hide \(title)" : "Show \(title)")
        }
    }
}
