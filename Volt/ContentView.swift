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
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                providerContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
            }
            .frame(height: 400)

            Divider()
            footer
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
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
            VoltLogoView(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Volt")
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                Text("AI plan usage")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isLoading(store.selectedProvider) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(store.isConfigured(store.selectedProvider)
                        ? store.selectedProvider.tint
                        : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(store.isConfigured(store.selectedProvider) ? "Connected" : "Not connected")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(snapshot.provider.displayName) usage")
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle = snapshot.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.bottom, 14)

            if let error = store.error(for: snapshot.provider) {
                staleDataBanner(error)
                    .padding(.bottom, 14)
            }

            ForEach(snapshot.notices) { notice in
                noticeView(notice)
                    .padding(.bottom, 10)
            }

            if snapshot.sections.isEmpty && snapshot.detailSections.isEmpty {
                Text("No active usage limits were returned for this account.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                ForEach(Array(snapshot.sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 {
                        Divider()
                            .padding(.vertical, 15)
                    }
                    usageSection(section, tint: snapshot.provider.tint)
                }

                ForEach(snapshot.detailSections) { section in
                    Divider()
                        .padding(.vertical, 15)
                    detailSection(section)
                }
            }

            Divider()
                .padding(.top, 16)
                .padding(.bottom, 11)

            providerHelpLink(snapshot.provider)
                .font(.system(size: 10.5))
        }
    }

    private func usageSection(_ section: UsageSection, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 12.5, weight: .semibold))
                if let subtitle = section.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(section.windows.enumerated()), id: \.element.id) { index, window in
                if index > 0 {
                    Divider()
                        .opacity(0.65)
                }
                UsageRowView(window: window, tint: tint)
            }
        }
    }

    private func detailSection(_ section: UsageDetailSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.system(size: 12.5, weight: .semibold))

            ForEach(section.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 11.5))
                        if let detail = item.detail {
                            Text(detail)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 12)
                    Text(item.value)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func noticeView(_ notice: UsageNotice) -> some View {
        let color: Color = notice.kind == .error ? .red : (notice.kind == .warning ? .orange : .secondary)
        let symbol = notice.kind == .information ? "info.circle.fill" : "exclamationmark.triangle.fill"
        return Label(notice.message, systemImage: symbol)
            .font(.system(size: 10.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func staleDataBanner(_ message: String) -> some View {
        Label("Showing the last update. \(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10.5))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var loadingView: some View {
        VStack(spacing: 11) {
            ProgressView()
            Text("Loading usage…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func unconfiguredView(_ provider: AIProvider) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 25, weight: .medium))
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
            .tint(provider.tint)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, minHeight: 270)
    }

    private func errorView(_ message: String, provider: AIProvider) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
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
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, minHeight: 270)
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            HStack(spacing: 14) {
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
            .padding(.vertical, 10)
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
            return "Import Claude Code credentials for the most reliable connection. A claude.ai browser session remains available as a fallback."
        case .openAI:
            return "Import the auth.json created by Codex. Volt stores a private copy in your Mac’s Keychain."
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
            title = "Open the Codex usage dashboard"
        }
        return Link(title, destination: url)
    }
}
