import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            header

            Picker("Provider", selection: $store.selectedProvider) {
                ForEach(AIProvider.allCases) { provider in
                    Label(provider.displayName, systemImage: provider.systemImage)
                        .tag(provider)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                providerContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
            .frame(height: 360)

            Divider()
            footer
        }
        .frame(width: 370)
        .background(
            LinearGradient(
                colors: [
                    store.selectedProvider.tint.opacity(0.07),
                    VoltTheme.alternate.opacity(0.025),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task(id: store.selectedProvider) {
            let provider = store.selectedProvider
            await store.refreshIfNeeded(provider)

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: UsageStore.refreshInterval)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await store.refresh(provider)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VoltLogoView(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Volt")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("AI usage at a glance")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(store.selectedProvider.tint.gradient)
                .frame(width: 8, height: 8)
                .shadow(color: store.selectedProvider.tint.opacity(0.5), radius: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var providerContent: some View {
        let provider = store.selectedProvider

        if let snapshot = store.snapshot(for: provider) {
            snapshotView(snapshot)
        } else if store.isLoading(provider) {
            loadingView
        } else if !store.isConfigured(provider) {
            unconfiguredView(provider)
        } else if let error = store.error(for: provider) {
            errorView(error, provider: provider)
        } else {
            loadingView
        }
    }

    private func snapshotView(_ snapshot: ProviderUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snapshot.provider.displayName) usage")
                        .font(.system(size: 15, weight: .semibold))
                    if let subtitle = snapshot.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                if store.isLoading(snapshot.provider) {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let error = store.error(for: snapshot.provider) {
                staleDataBanner(error)
            }

            if snapshot.windows.isEmpty {
                Text("No active usage windows were returned for this account.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(snapshot.windows) { window in
                    UsageRowView(window: window, tint: snapshot.provider.tint)
                }
            }

            if !snapshot.credits.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    Text("Credits & extra usage")
                        .font(.system(size: 12, weight: .semibold))
                    ForEach(snapshot.credits.indices, id: \.self) { index in
                        let row = snapshot.credits[index]
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title)
                                    .font(.system(size: 11.5))
                                if let detail = row.detail {
                                    Text(detail)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Text(row.value)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }

            providerHelpLink(snapshot.provider)
                .font(.system(size: 10.5))
        }
    }

    private func staleDataBanner(_ message: String) -> some View {
        Label {
            Text("Showing the last update. \(message)")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.orange)
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading usage…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
    }

    private func unconfiguredView(_ provider: AIProvider) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(provider.tint)
            Text("Connect \(provider.displayName)")
                .font(.system(size: 14, weight: .semibold))
            Text(configurationInstructions(for: provider))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            SettingsLink {
                Text("Open Settings")
            }
            .buttonStyle(.borderedProminent)
            .tint(VoltTheme.primary)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 210)
    }

    private func errorView(_ message: String, provider: AIProvider) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
            Text("Couldn’t load \(provider.displayName)")
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Try Again") {
                    Task { await store.refresh(provider) }
                }
                SettingsLink {
                    Text("Settings")
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 210)
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            HStack(spacing: 13) {
                if let updatedAt = store.snapshot(for: store.selectedProvider)?.updatedAt {
                    Text(updatedDescription(updatedAt, now: timeline.date))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    Text(store.selectedProvider.companyName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await store.refreshSelected() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(store.isLoading(store.selectedProvider) || !store.isConfigured(store.selectedProvider))
                .help("Refresh usage")

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .help("Quit Volt")
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private func updatedDescription(_ date: Date, now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(date)), 0)
        if seconds < 60 { return "Updated just now" }
        if seconds < 3600 { return "Updated \(seconds / 60) min ago" }
        return "Updated \(seconds / 3600) hr ago"
    }

    private func configurationInstructions(for provider: AIProvider) -> String {
        switch provider {
        case .anthropic:
            "Add your Claude organization ID and session key. Credentials stay in your Mac’s Keychain."
        case .openAI:
            "Import the auth.json created by Codex, or enter an OpenAI OAuth access token manually."
        }
    }

    private func providerHelpLink(_ provider: AIProvider) -> some View {
        let url: URL
        let title: String
        switch provider {
        case .anthropic:
            url = URL(string: "https://support.claude.com/en/articles/11647753-understanding-usage-and-length-limits")!
            title = "Learn about Claude usage limits"
        case .openAI:
            url = URL(string: "https://chatgpt.com/codex/settings/usage")!
            title = "Open OpenAI usage dashboard"
        }
        return Link(title, destination: url)
    }
}
