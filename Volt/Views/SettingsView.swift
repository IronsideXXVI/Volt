import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    @EnvironmentObject private var updates: UpdateController

    @State private var selectedProvider = AIProvider.anthropic
    @State private var organizationID = ""
    @State private var claudeSessionKey = ""
    @State private var openAIAccessToken = ""
    @State private var openAIRefreshToken = ""
    @State private var openAIIDToken = ""
    @State private var openAIAccountID = ""
    @State private var openAILastRefresh: Date?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var providerToDisconnect: AIProvider?

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Divider()

            Form {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Label(provider.displayName, systemImage: provider.systemImage)
                            .tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                GroupBox {
                    switch selectedProvider {
                    case .anthropic:
                        claudeSettings
                    case .openAI:
                        openAISettings
                    }
                } label: {
                    Label("\(selectedProvider.displayName) connection", systemImage: "key.fill")
                }

                GroupBox {
                    updateSettings
                } label: {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }

                if let statusMessage {
                    Label(
                        statusMessage,
                        systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.system(size: 11.5))
                    .foregroundStyle(statusIsError ? Color.orange : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(18)

            Divider()
            actionBar
        }
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: loadCredentials)
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

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            VoltLogoView(size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Volt Settings")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Credentials are encrypted in your login Keychain and sent only to their provider.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [VoltTheme.primary.opacity(0.10), VoltTheme.alternate.opacity(0.04)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private var claudeSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Organization ID", text: $organizationID)
                .textFieldStyle(.roundedBorder)
            SecureField("Session key", text: $claudeSessionKey)
                .textFieldStyle(.roundedBorder)

            Text("Find the organization ID in a claude.ai API request URL and copy the sessionKey cookie from your signed-in browser session.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            connectionStatus(for: .anthropic)
        }
        .padding(.vertical, 6)
    }

    private var openAISettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    importCodexCredentials()
                } label: {
                    Label("Import Codex auth.json", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(AIProvider.openAI.tint)

                Text("Recommended")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Divider()

            SecureField("OAuth access token", text: $openAIAccessToken)
                .textFieldStyle(.roundedBorder)
            TextField("ChatGPT account ID (optional)", text: $openAIAccountID)
                .textFieldStyle(.roundedBorder)
            SecureField("OAuth refresh token (optional)", text: $openAIRefreshToken)
                .textFieldStyle(.roundedBorder)

            Text("Import reads the credentials created by `codex login`. Volt stores a private copy in Keychain so it can refresh the token without repeatedly reading the file.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                "OpenAI plan limits use the same authenticated usage endpoint as Codex. This endpoint is not a public OpenAI API and may change.",
                systemImage: "info.circle"
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            connectionStatus(for: .openAI)
        }
        .padding(.vertical, 6)
    }

    private var updateSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "Automatically check for updates",
                isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.automaticallyChecksForUpdates = $0 }
                )
            )

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
        .padding(.vertical, 6)
    }

    private func connectionStatus(for provider: AIProvider) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.isConfigured(provider) ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
            Text(store.isConfigured(provider) ? "Connected" : "Not connected")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Disconnect \(selectedProvider.displayName)…", role: .destructive) {
                providerToDisconnect = selectedProvider
            }
            .disabled(!store.isConfigured(selectedProvider))

            Spacer()

            Button("Save & Refresh") {
                saveAndRefresh()
            }
            .buttonStyle(.borderedProminent)
            .tint(VoltTheme.primary)
        }
        .padding(18)
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
        do {
            let claude = try store.claudeCredentials()
            organizationID = claude.organizationID
            claudeSessionKey = claude.sessionKey

            let openAI = try store.openAICredentials()
            openAIAccessToken = openAI.accessToken
            openAIRefreshToken = openAI.refreshToken
            openAIIDToken = openAI.idToken
            openAIAccountID = openAI.accountID
            openAILastRefresh = openAI.lastRefresh
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    private func saveAndRefresh() {
        do {
            try store.saveClaude(
                ClaudeCredentials(
                    organizationID: organizationID.trimmingCharacters(in: .whitespacesAndNewlines),
                    sessionKey: claudeSessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            try store.saveOpenAI(
                OpenAICredentials(
                    accessToken: openAIAccessToken.trimmingCharacters(in: .whitespacesAndNewlines),
                    refreshToken: openAIRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines),
                    idToken: openAIIDToken.trimmingCharacters(in: .whitespacesAndNewlines),
                    accountID: openAIAccountID.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastRefresh: openAILastRefresh
                )
            )
            showStatus("Credentials saved. Refreshing connected providers…", isError: false)
            Task {
                await store.refresh(.anthropic)
                await store.refresh(.openAI)
                if let error = store.error(for: selectedProvider) {
                    showStatus(error, isError: true)
                } else {
                    showStatus("Saved and refreshed successfully.", isError: false)
                }
            }
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    private func importCodexCredentials() {
        let panel = NSOpenPanel()
        panel.title = "Choose Codex auth.json"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true

        let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        if FileManager.default.fileExists(atPath: defaultDirectory.path) {
            panel.directoryURL = defaultDirectory
        }
        panel.nameFieldStringValue = "auth.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let credentials = try OpenAICredentials.imported(from: data)
            openAIAccessToken = credentials.accessToken
            openAIRefreshToken = credentials.refreshToken
            openAIIDToken = credentials.idToken
            openAIAccountID = credentials.accountID
            openAILastRefresh = credentials.lastRefresh
            showStatus("Imported Codex credentials. Select Save & Refresh to connect.", isError: false)
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    private func disconnectSelectedProvider() {
        guard let provider = providerToDisconnect else { return }
        defer { providerToDisconnect = nil }
        do {
            try store.disconnect(provider)
            switch provider {
            case .anthropic:
                organizationID = ""
                claudeSessionKey = ""
            case .openAI:
                openAIAccessToken = ""
                openAIRefreshToken = ""
                openAIIDToken = ""
                openAIAccountID = ""
                openAILastRefresh = nil
            }
            showStatus("\(provider.displayName) disconnected.", isError: false)
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
