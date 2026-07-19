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
        case .general: return "slider.horizontal.3"
        case .claude: return "sparkle"
        case .openAI: return "brain"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }

    var groupTitle: String {
        switch self {
        case .general: return "Workspace"
        case .claude, .openAI: return "Connections"
        case .updates: return "System"
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

    private var paneTint: Color {
        switch selectedPane {
        case .claude: return AIProvider.anthropic.tint
        case .openAI: return AIProvider.openAI.tint
        case .updates: return .green
        case .general: return VoltTheme.primary
        }
    }

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

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                VoltLogoView(size: 20)
                Text("Volt")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 20)

            sidebarGroup("Workspace", panes: [.general])
            sidebarGroup("Connections", panes: [.claude, .openAI])
            sidebarGroup("System", panes: [.updates])

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("Secrets stay in Keychain", systemImage: "lock.shield.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Volt \(appVersion)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 190)
        .background(.ultraThinMaterial)
    }

    private func sidebarGroup(_ title: String, panes: [SettingsPane]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.bottom, 3)

            ForEach(panes) { pane in
                sidebarButton(pane)
            }
        }
        .padding(.bottom, 18)
    }

    private func sidebarButton(_ pane: SettingsPane) -> some View {
        let provider: AIProvider? = switch pane {
        case .claude: .anthropic
        case .openAI: .openAI
        case .general, .updates: nil
        }
        let isSelected = selectedPane == pane
        let tint = provider?.tint ?? (pane == .updates ? Color.green : VoltTheme.primary)

        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                selectedPane = pane
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? tint : .secondary)
                    .frame(width: 18)

                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer(minLength: 4)

                if let provider {
                    Circle()
                        .fill(connectionColor(for: provider))
                        .frame(width: 6, height: 6)
                        .accessibilityLabel(connectionTitle(for: provider))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
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
                SectionHeader("Default dashboard", detail: "The provider Volt shows when it opens.")
                VStack(spacing: 8) {
                    ForEach(AIProvider.allCases) { provider in
                        defaultProviderButton(provider)
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

                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.automaticallyChecksForUpdates = $0 }
                    )
                )
                .font(.system(size: 13))

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Installed version")
                            .font(.system(size: 13))
                        Text(appVersion)
                            .font(.system(size: 11, design: .monospaced))
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
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
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
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
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
                    connectionStatusCard(for: provider)
                    content()
                    statusBanner(for: provider)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            actionFooter(for: provider, save: save)
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
            Text(selectedPane.groupTitle.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(paneTint)
            Text(title)
                .font(.system(size: 20, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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

    private func connectionStatusCard(for provider: AIProvider) -> some View {
        HStack(spacing: 12) {
            VoltGlyph(symbol: provider.systemImage, tint: provider.tint, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(connectionTitle(for: provider))
                    .font(.system(size: 13, weight: .semibold))
                Text(connectionDetail(for: provider))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            statusChip(
                title: store.isConfigured(provider) ? "Configured" : "Setup required",
                color: connectionColor(for: provider),
                symbol: store.isConfigured(provider) ? "checkmark" : "plus"
            )
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
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                statusChip(title: "Recommended", color: provider.tint, symbol: "star.fill")
            }

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: action) {
                    Label(buttonTitle, systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(provider.tint)

                if isReady {
                    statusChip(title: "Credential ready", color: .green, symbol: "checkmark")
                }
            }
        }
        .voltCard()
    }

    private func advancedLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private func defaultProviderButton(_ provider: AIProvider) -> some View {
        let isSelected = store.selectedProvider == provider

        return Button {
            store.selectedProvider = provider
        } label: {
            HStack(spacing: 10) {
                VoltGlyph(symbol: provider.systemImage, tint: provider.tint, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(provider.companyName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? provider.tint : Color.secondary.opacity(0.4))
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? provider.tint.opacity(0.08) : VoltTheme.card,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? provider.tint.opacity(0.22) : VoltTheme.hairline, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func securityRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func statusChip(title: String, color: Color, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func actionFooter(for provider: AIProvider, save: @escaping () -> Void) -> some View {
        HStack {
            Button("Disconnect…", role: .destructive) {
                providerToDisconnect = provider
            }
            .disabled(
                (!store.isConfigured(provider) && statuses[provider]?.kind != .error)
                    || testingProviders.contains(provider)
            )

            Spacer()

            if dirtyProviders.contains(provider) {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(provider.tint)
            }

            Button(action: save) {
                HStack(spacing: 7) {
                    if testingProviders.contains(provider) {
                        ProgressView().controlSize(.small)
                    }
                    Text(testingProviders.contains(provider) ? "Testing…" : "Save & Test")
                }
                .frame(minWidth: 78)
            }
            .buttonStyle(.borderedProminent)
            .tint(provider.tint)
            .disabled(store.isLoading(provider) || testingProviders.contains(provider))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: Connection copy helpers

    private func connectionTitle(for provider: AIProvider) -> String {
        if testingProviders.contains(provider) || store.isLoading(provider) { return "Testing connection…" }
        if dirtyProviders.contains(provider) { return "Unsaved changes" }
        if store.snapshot(for: provider) != nil, store.error(for: provider) == nil { return "Connected" }
        if store.isConfigured(provider) { return "Credentials saved" }
        return "Not connected"
    }

    private func connectionDetail(for provider: AIProvider) -> String {
        if dirtyProviders.contains(provider) {
            return "Save and test these changes before Volt uses them."
        }
        if let snapshot = store.snapshot(for: provider), let subtitle = snapshot.subtitle {
            return subtitle
        }
        if let error = store.error(for: provider) {
            return error
        }
        return store.isConfigured(provider)
            ? "Save & Test to verify the current credentials"
            : "Import credentials below to connect this provider"
    }

    private func connectionColor(for provider: AIProvider) -> Color {
        if testingProviders.contains(provider) || dirtyProviders.contains(provider) { return provider.tint }
        if store.snapshot(for: provider) != nil, store.error(for: provider) == nil { return .green }
        if store.error(for: provider) != nil { return .orange }
        return store.isConfigured(provider) ? provider.tint : Color.secondary.opacity(0.4)
    }

    // MARK: Credential state

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
