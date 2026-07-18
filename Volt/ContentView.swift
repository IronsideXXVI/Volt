import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            appHeader
            providerSwitcher(selection: $store.selectedProvider)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            Rectangle()
                .fill(VoltTheme.hairline)
                .frame(height: 0.5)

            ScrollView {
                providerContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            }
            .frame(height: 462)
            .scrollIndicators(.automatic)

            Rectangle()
                .fill(VoltTheme.hairline)
                .frame(height: 0.5)
            footer
        }
        .frame(width: 430)
        .background(VoltTheme.canvas)
        .tint(VoltTheme.primary)
        .task(id: store.selectedProvider) {
            let provider = store.selectedProvider
            await store.refreshIfNeeded(provider)

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: store.refreshDelay(for: provider))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await store.refresh(provider)
            }
        }
    }

    private var appHeader: some View {
        HStack(spacing: 11) {
            VoltLogoView(size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Volt")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Usage intelligence")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            connectionIndicator(for: store.selectedProvider)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func providerSwitcher(selection: Binding<AIProvider>) -> some View {
        HStack(spacing: 5) {
            ForEach(AIProvider.allCases) { provider in
                let isSelected = selection.wrappedValue == provider
                Button {
                    selection.wrappedValue = provider
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: provider.systemImage)
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(provider.displayName)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        Spacer(minLength: 0)
                        Circle()
                            .fill(headerStatusColor(for: provider))
                            .frame(width: 6, height: 6)
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 11)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        isSelected ? VoltTheme.elevatedSurface : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(provider.tint.opacity(0.28), lineWidth: 0.75)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(provider.displayName) usage")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(VoltTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(VoltTheme.hairline, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func connectionIndicator(for provider: AIProvider) -> some View {
        if store.isLoading(provider) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Syncing")
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Circle()
                    .fill(headerStatusColor(for: provider))
                    .frame(width: 7, height: 7)
                Text(headerStatusLabel(for: provider))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headerStatusLabel(for: provider))
        }
    }

    private func headerStatusColor(for provider: AIProvider) -> Color {
        if store.error(for: provider) != nil { return .orange }
        if store.snapshot(for: provider) != nil { return .green }
        if store.isConfigured(provider) { return provider.tint }
        return Color.secondary.opacity(0.35)
    }

    private func headerStatusLabel(for provider: AIProvider) -> String {
        if store.error(for: provider) != nil {
            return store.snapshot(for: provider) == nil ? "Needs attention" : "Saved data"
        }
        if store.snapshot(for: provider) != nil { return "Connected" }
        return store.isConfigured(provider) ? "Ready" : "Not connected"
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
        VStack(alignment: .leading, spacing: 13) {
            snapshotHeader(snapshot)

            if let error = store.error(for: snapshot.provider) {
                staleDataBanner(error)
            }

            ForEach(snapshot.notices) { notice in
                noticeView(notice)
            }

            if snapshot.sections.isEmpty && snapshot.detailSections.isEmpty {
                emptyUsageView
            } else {
                if !snapshot.sections.isEmpty {
                    usageLegend(tint: snapshot.provider.tint)
                }

                ForEach(snapshot.sections) { section in
                    usageSection(section, tint: snapshot.provider.tint)
                }

                ForEach(snapshot.detailSections) { section in
                    detailSection(section)
                }
            }

            providerHelpLink(snapshot.provider)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 2)
                .padding(.top, 2)
        }
    }

    private func snapshotHeader(_ snapshot: ProviderUsageSnapshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(snapshot.provider.tint.opacity(0.12))
                Image(systemName: snapshot.provider.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(snapshot.provider.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(snapshot.provider.displayName) usage")
                    .font(.system(size: 15, weight: .bold))

                Text(snapshot.account?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                     ?? snapshot.provider.companyName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            if let plan = snapshot.plan?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                Text(plan)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(snapshot.provider.tint)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(snapshot.provider.tint.opacity(0.11), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(snapshot.provider.tint.opacity(0.18), lineWidth: 0.5)
                    }
                    .frame(maxWidth: 145)
                    .help(plan)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [snapshot.provider.tint.opacity(0.08), VoltTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(snapshot.provider.tint.opacity(0.18), lineWidth: 0.75)
        }
    }

    private func usageLegend(tint: Color) -> some View {
        HStack(spacing: 14) {
            legendItem(color: tint, title: "Quota used")
            legendItem(color: VoltTheme.windowElapsed, title: "Window elapsed")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 13, height: 5)
            Text(title)
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private func usageSection(_ section: UsageSection, tint: Color) -> some View {
        VoltSurface {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .bold))
                    if let subtitle = section.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(Array(section.windows.enumerated()), id: \.element.id) { index, window in
                    if index > 0 {
                        Rectangle()
                            .fill(VoltTheme.hairline)
                            .frame(height: 0.5)
                    }
                    UsageRowView(
                        window: window,
                        tint: tint,
                        showsTitle: !(section.windows.count == 1 && section.title == window.title)
                    )
                }
            }
        }
    }

    private func detailSection(_ section: UsageDetailSection) -> some View {
        VoltSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text(section.title)
                    .font(.system(size: 13, weight: .bold))

                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(VoltTheme.hairline)
                            .frame(height: 0.5)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 11.5, weight: .medium))
                            if let detail = item.detail {
                                Text(detail)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer(minLength: 12)

                        Text(item.value)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .layoutPriority(1)
                    }
                }
            }
        }
    }

    private var emptyUsageView: some View {
        VoltSurface {
            VStack(spacing: 9) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 22, weight: .medium))
                Text("No active usage limits")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("This provider did not return any dashboard fields for the account.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private func noticeView(_ notice: UsageNotice) -> some View {
        let color: Color = notice.kind == .error ? .red : (notice.kind == .warning ? .orange : .secondary)
        let symbol = notice.kind == .information ? "info.circle.fill" : "exclamationmark.triangle.fill"
        return Label(notice.message, systemImage: symbol)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(0.16), lineWidth: 0.5)
            }
    }

    private func staleDataBanner(_ message: String) -> some View {
        Label("Showing the last update. \(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading usage")
                .font(.system(size: 12.5, weight: .semibold))
            Text("Connecting directly to \(store.selectedProvider.companyName)…")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func unconfiguredView(_ provider: AIProvider) -> some View {
        VoltSurface {
            VStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(provider.tint.opacity(0.11))
                    Image(systemName: "key.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(provider.tint)
                }
                .frame(width: 48, height: 48)

                Text("Connect \(provider.displayName)")
                    .font(.system(size: 15, weight: .bold))
                Text(configurationInstructions(for: provider))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsLink {
                    Label("Open Settings", systemImage: "arrow.up.forward")
                }
                .buttonStyle(.borderedProminent)
                .tint(provider.tint)
                .controlSize(.large)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 340)
    }

    private func errorView(_ message: String, provider: AIProvider) -> some View {
        VoltSurface {
            VStack(spacing: 13) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(.orange)
                Text("Couldn’t load \(provider.displayName)")
                    .font(.system(size: 15, weight: .bold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Try Again") {
                        Task { await store.refresh(provider) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(provider.tint)

                    SettingsLink {
                        Text("Settings")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 340)
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            HStack(spacing: 7) {
                if let updatedAt = store.snapshot(for: store.selectedProvider)?.updatedAt {
                    Label(updatedDescription(updatedAt, now: timeline.date), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Text(store.selectedProvider.companyName)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                footerButton(symbol: "arrow.clockwise", help: "Refresh usage") {
                    Task { await store.refreshSelected() }
                }
                .disabled(store.isLoading(store.selectedProvider) || !store.isConfigured(store.selectedProvider))
                .keyboardShortcut("r", modifiers: .command)

                SettingsLink {
                    Image(systemName: "gearshape")
                        .frame(width: 27, height: 27)
                        .background(VoltTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Open Settings")
                .keyboardShortcut(",", modifiers: .command)

                footerButton(symbol: "power", help: "Quit Volt") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
        }
    }

    private func footerButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 27, height: 27)
                .background(VoltTheme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func updatedDescription(_ date: Date, now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(date)), 0)
        if seconds < 60 { return "Updated just now" }
        if seconds < 3600 { return "Updated \(seconds / 60) min ago" }
        if seconds < 24 * 3600 { return "Updated \(seconds / 3600) hr ago" }
        return "Updated \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
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
        return Link(destination: url) {
            Label(title, systemImage: "arrow.up.right")
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
