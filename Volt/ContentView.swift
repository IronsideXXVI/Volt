import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        @Bindable var store = store

        ZStack {
            VoltBackdrop(tint: store.selectedProvider.tint)

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
                .frame(height: 474)
                .scrollIndicators(.automatic)

                footer
            }
        }
        .frame(width: 440)
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
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(VoltTheme.brandGradient)
                    .shadow(color: VoltTheme.primary.opacity(0.22), radius: 9, y: 3)
                VoltLogoView(size: 27)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Volt")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("AI USAGE")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.65)
                        .foregroundStyle(VoltTheme.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(VoltTheme.primary.opacity(0.10), in: Capsule())
                }
                Text("Know your limits before they slow you down")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            connectionIndicator(for: store.selectedProvider)
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 13)
    }

    private func providerSwitcher(selection: Binding<AIProvider>) -> some View {
        HStack(spacing: 4) {
            ForEach(AIProvider.allCases) { provider in
                let isSelected = selection.wrappedValue == provider
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection.wrappedValue = provider
                    }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(isSelected ? provider.tint.opacity(0.16) : Color.primary.opacity(0.055))
                            Image(systemName: provider.systemImage)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(isSelected ? provider.tint : Color.secondary)
                        }
                        .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(provider.displayName)
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(headerStatusLabel(for: provider))
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Circle()
                            .fill(headerStatusColor(for: provider))
                            .frame(width: 6, height: 6)
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(VoltTheme.surface)
                                .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
                        }
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(provider.tint.opacity(0.25), lineWidth: 0.75)
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
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
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
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(VoltTheme.elevatedSurface, in: Capsule())
        } else {
            VoltStatusPill(
                title: headerStatusLabel(for: provider),
                color: headerStatusColor(for: provider)
            )
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
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [snapshot.provider.tint.opacity(0.16), snapshot.provider.tint.opacity(0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(snapshot.provider.tint.opacity(0.09))
                .frame(width: 130, height: 130)
                .blur(radius: 22)
                .offset(x: 34, y: -58)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VoltIconTile(
                        symbol: snapshot.provider.systemImage,
                        tint: snapshot.provider.tint,
                        size: 43,
                        symbolSize: 16
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.provider.displayName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))

                        Text(snapshot.account?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                             ?? snapshot.provider.companyName)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 8)

                    if let plan = snapshot.plan?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                        VoltStatusPill(title: plan, color: snapshot.provider.tint, symbol: "bolt.fill")
                            .frame(maxWidth: 150)
                            .help(plan)
                    }
                }

                HStack(spacing: 16) {
                    summaryMetric(
                        value: "\(snapshot.windows.count)",
                        label: snapshot.windows.count == 1 ? "active limit" : "active limits"
                    )
                    Rectangle()
                        .fill(snapshot.provider.tint.opacity(0.18))
                        .frame(width: 0.5, height: 25)
                    summaryMetric(
                        value: "Live",
                        label: "direct provider data"
                    )
                    Spacer()
                }
            }
            .padding(15)
        }
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(snapshot.provider.tint.opacity(0.22), lineWidth: 0.75)
        }
        .shadow(color: snapshot.provider.tint.opacity(0.08), radius: 12, y: 4)
    }

    private func summaryMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func usageLegend(tint: Color) -> some View {
        HStack(spacing: 13) {
            VoltSectionLabel(title: "Usage pace", symbol: "chart.xyaxis.line")
            Spacer(minLength: 4)
            legendItem(color: tint, title: "Used")
            legendItem(color: VoltTheme.windowElapsed, title: "Time")
        }
        .padding(.horizontal, 3)
        .padding(.top, 2)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    private func usageSection(_ section: UsageSection, tint: Color) -> some View {
        VoltSurface(accent: tint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        if let subtitle = section.subtitle {
                            Text(subtitle)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(section.windows.count) WINDOW\(section.windows.count == 1 ? "" : "S")")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.45)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.09), in: Capsule())
                }

                ForEach(Array(section.windows.enumerated()), id: \.element.id) { index, window in
                    if index > 0 {
                        Rectangle()
                            .fill(VoltTheme.hairline)
                            .frame(height: 0.5)
                            .padding(.vertical, 1)
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
            VStack(alignment: .leading, spacing: 13) {
                VoltSectionLabel(title: section.title, symbol: "list.bullet.rectangle")

                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(VoltTheme.hairline)
                            .frame(height: 0.5)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 11.5, weight: .semibold))
                            if let detail = item.detail {
                                Text(detail)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer(minLength: 12)

                        Text(item.value)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(VoltTheme.primary)
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
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(store.selectedProvider.tint.opacity(0.11))
                ProgressView()
                    .controlSize(.regular)
                    .tint(store.selectedProvider.tint)
            }
            .frame(width: 58, height: 58)

            VStack(spacing: 4) {
                Text("Syncing \(store.selectedProvider.displayName)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("Pulling the latest limits directly from \(store.selectedProvider.companyName)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 350)
    }

    private func unconfiguredView(_ provider: AIProvider) -> some View {
        VoltSurface(cornerRadius: 18, padding: 0, accent: provider.tint) {
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    VoltIconTile(symbol: "key.fill", tint: provider.tint, size: 58, symbolSize: 20)

                    VStack(spacing: 5) {
                        Text("Connect \(provider.displayName)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text(configurationInstructions(for: provider))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsLink {
                        Label("Set up \(provider.displayName)", systemImage: "arrow.right")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(provider.tint)
                    .controlSize(.large)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 34)

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                    Text("Credentials stay encrypted in your Mac’s Keychain")
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.primary.opacity(0.025))
            }
        }
        .frame(minHeight: 350)
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
                HStack(spacing: 6) {
                    Circle()
                        .fill(headerStatusColor(for: store.selectedProvider))
                        .frame(width: 6, height: 6)
                    if let updatedAt = store.snapshot(for: store.selectedProvider)?.updatedAt {
                        Text(updatedDescription(updatedAt, now: timeline.date))
                    } else {
                        Text(store.selectedProvider.companyName)
                    }
                }
                .foregroundStyle(.secondary)

                Spacer()

                footerButton(symbol: "arrow.clockwise", help: "Refresh usage") {
                    Task { await store.refreshSelected() }
                }
                .disabled(store.isLoading(store.selectedProvider) || !store.isConfigured(store.selectedProvider))
                .keyboardShortcut("r", modifiers: .command)

                SettingsLink {
                    Image(systemName: "gearshape.fill")
                        .frame(width: 29, height: 29)
                        .background(VoltTheme.elevatedSurface, in: Circle())
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
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(VoltTheme.hairline)
                    .frame(height: 0.5)
            }
        }
    }

    private func footerButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 29, height: 29)
                .background(VoltTheme.elevatedSurface, in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
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
