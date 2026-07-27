import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    @State private var contentHeight: CGFloat = 0

    private let width: CGFloat = 360
    private let maxContentHeight: CGFloat = 520

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            header

            accountSwitcher(selection: $store.selectedAccountID)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                providerContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        }
                    )
            }
            .frame(height: min(max(contentHeight, 120), maxContentHeight))
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }

            Divider()

            footer
        }
        .frame(width: width)
        .tint(store.selectedProvider.tint)
        // Fetch only when the menu opens. An unstructured Task is used (rather
        // than .task(id:)) so the fetch runs to completion and is not cancelled
        // by the view re-renders that happen while the popover is open.
        // Switching account tabs does not fetch, and there is no background
        // polling; the refresh button is the only other trigger.
        .onAppear {
            Task { await store.refreshOnOpen() }
        }
    }

    /// Brings Volt to the foreground and opens Settings. Volt is an agent app
    /// (LSUIElement), so without an explicit activate the Settings window would
    /// open behind whatever app is frontmost. The MenuBarExtra popover doesn't
    /// dismiss on its own here, so we close it explicitly: while it's shown it is
    /// the process's key window (that's why ⌘R/⌘, work inside it), captured
    /// before focus moves to the Settings window.
    private func showSettings() {
        let dashboard = NSApp.keyWindow
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        dashboard?.close()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 9) {
            VoltLogoView(size: 19)
            Text("Volt - AI subscription usage tracker")
                .voltHeaderTitle()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
    }

    // MARK: Account switcher

    private func accountSwitcher(selection: Binding<UUID>) -> some View {
        let visibleTabCount = CGFloat(min(max(store.accounts.count, 1), 3))
        let tabWidth = (326 - (visibleTabCount - 1) * 3) / visibleTabCount

        return ScrollView(.horizontal) {
            HStack(spacing: 3) {
                ForEach(store.accounts) { account in
                    let isSelected = selection.wrappedValue == account.id
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            selection.wrappedValue = account.id
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(account.provider.logoAsset)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 15, height: 15)
                            Text(account.displayName)
                                .voltTabLabel(selected: isSelected)
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 11)
                        .frame(width: tabWidth)
                        .frame(minHeight: 32)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(VoltTheme.cardHover)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(VoltTheme.hairline, lineWidth: 0.5)
                                    }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(account.displayName) usage")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(3)
        }
        .scrollIndicators(.hidden)
        .background(VoltTheme.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: Content router

    @ViewBuilder
    private var providerContent: some View {
        let account = store.selectedAccount

        if let snapshot = store.snapshot(for: account.id) {
            snapshotView(snapshot, accountID: account.id)
        } else if store.isLoading(account.id) {
            loadingView
        } else if !store.isConfigured(account.id) {
            unconfiguredView(account)
        } else if let error = store.error(for: account.id) {
            errorView(error, account: account)
        } else {
            loadingView
        }
    }

    // MARK: Snapshot

    private func snapshotView(_ snapshot: ProviderUsageSnapshot, accountID: UUID) -> some View {
        let boostNotices = snapshot.notices.filter { $0.id.hasPrefix("claude-boost-") }
        let otherNotices = snapshot.notices.filter { !$0.id.hasPrefix("claude-boost-") }
        let isClaude = snapshot.provider == .anthropic
        let hasWeeklySection = snapshot.sections.contains { $0.id == "claude-weekly-limits" }

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(snapshot.provider.displayName) plan usage limits")
                    .voltTitle()
                if let account = trimmed(snapshot.account) {
                    Text(account)
                        .voltCaption()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if let plan = trimmed(snapshot.plan) {
                    Text(plan)
                        .voltCaption()
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let error = store.error(for: accountID) {
                banner(error, color: .orange, symbol: "exclamationmark.triangle.fill", prefix: "Showing the last update. ")
            }

            ForEach(otherNotices) { notice in
                noticeView(notice)
            }

            // When there's no weekly-limits section to attach them to, still
            // surface the Claude boost banner and learn-more link.
            if isClaude && !hasWeeklySection {
                ForEach(boostNotices) { noticeView($0) }
                learnMoreLink
            }

            if snapshot.sections.isEmpty && snapshot.detailSections.isEmpty {
                emptyUsageView
            } else {
                ForEach(Array(snapshot.sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 { Divider() }
                    if isClaude && section.id == "claude-weekly-limits" {
                        usageSection(section, boostNotices: boostNotices, showLearnMore: true)
                    } else {
                        usageSection(section)
                    }
                }

                ForEach(snapshot.detailSections) { section in
                    Divider()
                    detailSection(section)
                }
            }
        }
    }

    /// Renders inline Markdown. Links are tinted with the Volt accent and
    /// underlined. `base` colors the whole string; `lead` colors the API's
    /// strongly-emphasized run (e.g. a banner's first sentence) without bolding
    /// it. When `base` is nil, the surrounding `foregroundStyle` applies.
    private func styledMarkdown(
        _ string: String,
        size: CGFloat = 11,
        weight: Font.Weight = .medium,
        base: Color? = nil,
        lead: Color? = nil
    ) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)

        attributed.font = .system(size: size, weight: weight)
        if let base {
            attributed.foregroundColor = base
        }
        if let lead {
            let leadRanges = attributed.runs
                .filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
                .map(\.range)
            for range in leadRanges {
                attributed[range].foregroundColor = lead
            }
        }
        let linkRanges = attributed.runs.filter { $0.link != nil }.map(\.range)
        for range in linkRanges {
            attributed[range].underlineStyle = .single
            attributed[range].foregroundColor = VoltTheme.primary
        }
        return attributed
    }

    /// The standalone "Learn more about usage limits" link (Claude).
    private var learnMoreLink: some View {
        Text(styledMarkdown(
            "[Learn more about usage limits](https://support.claude.com/en/articles/11647753-understanding-usage-and-length-limits)"
        ))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func usageSection(
        _ section: UsageSection,
        boostNotices: [UsageNotice] = [],
        showLearnMore: Bool = false
    ) -> some View {
        let isSelfTitled = section.windows.count == 1 && section.title == section.windows.first?.title

        return VStack(alignment: .leading, spacing: 12) {
            if !isSelfTitled {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .voltSectionHeader()
                    if let subtitle = section.subtitle {
                        Text(styledMarkdown(subtitle))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ForEach(boostNotices) { noticeView($0) }
            if showLearnMore {
                learnMoreLink
            }

            ForEach(section.windows) { window in
                UsageRowView(window: window, showsTitle: true)
            }
        }
    }

    private func detailSection(_ section: UsageDetailSection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .voltSectionHeader()
                if let subtitle = section.subtitle {
                    Text(styledMarkdown(subtitle))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(section.items) { item in
                if item.value.isEmpty {
                    Text(item.title)
                        .voltCaption()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .voltCaption()
                            if let detail = item.detail {
                                Text(detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(item.value)
                            .voltDetailValue()
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var emptyUsageView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.secondary)
            Text("No active usage limits")
                .voltStateTitle()
            Text("This provider did not return any dashboard fields for the account.")
                .voltCaption()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    // MARK: Banners & notices

    private func noticeView(_ notice: UsageNotice) -> some View {
        let isInfo = notice.kind == .information
        let isError = notice.kind == .error
        let foreground: Color = isError ? .red : .secondary
        let symbol = isInfo ? "info.circle.fill" : "exclamationmark.triangle.fill"
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foreground)
                .padding(.top, 1)
            Text(styledMarkdown(
                notice.message,
                base: foreground,
                lead: isError ? .red : .primary
            ))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isError ? Color.red.opacity(0.09) : VoltTheme.card,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if !isError {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(VoltTheme.hairline, lineWidth: 0.5)
            }
        }
    }

    private func banner(_ message: String, color: Color, symbol: String, prefix: String = "") -> some View {
        Label(prefix + message, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(store.selectedProvider.tint)
            Text("Syncing \(store.selectedProvider.displayName)")
                .voltStateTitle()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func unconfiguredView(_ account: ProviderAccount) -> some View {
        let provider = account.provider
        return VStack(spacing: 14) {
            VoltGlyph(symbol: "key.fill", tint: provider.tint, size: 46)

            VStack(spacing: 5) {
                Text("Connect \(account.displayName)")
                    .voltStateTitle()
                Text(configurationInstructions(for: provider))
                    .voltCaption()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: showSettings) {
                Text("Set up \(account.displayName)")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(provider.tint)
            .controlSize(.large)

            Label("Credentials stay in your Mac's Keychain", systemImage: "lock.shield.fill")
                .voltCaption()
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
    }

    private func errorView(_ message: String, account: ProviderAccount) -> some View {
        let provider = account.provider
        return VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text("Couldn't load \(account.displayName)")
                .voltStateTitle()
            Text(message)
                .voltCaption()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Try Again") {
                    Task { await store.refresh(account.id) }
                }
                .buttonStyle(.borderedProminent)
                .tint(provider.tint)

                Button("Settings", action: showSettings)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
    }

    // MARK: Footer

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            HStack(spacing: 8) {
                Group {
                    if let updatedAt = store.snapshot(for: store.selectedAccountID)?.updatedAt {
                        Text(updatedDescription(updatedAt, now: timeline.date))
                    } else {
                        Text(store.selectedAccount.provider.companyName)
                    }
                }
                .foregroundStyle(.secondary)

                Spacer()

                footerButton(symbol: "arrow.clockwise", help: "Refresh usage") {
                    Task { await store.refreshSelected() }
                }
                .disabled(store.isLoading(store.selectedAccountID) || !store.isConfigured(store.selectedAccountID))
                .keyboardShortcut("r", modifiers: .command)

                Button(action: showSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Settings")
                .accessibilityLabel("Open Settings")
                .keyboardShortcut(",", modifiers: .command)

                footerButton(symbol: "power", help: "Quit Volt") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .voltFooterText()
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    private func footerButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: Status helpers

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
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
            return "Import Claude Code credentials for the most reliable connection. A claude.ai browser session works as a fallback."
        case .openAI:
            return "Import the auth.json created by Codex. Volt stores a private copy in your Mac's Keychain."
        }
    }

}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
