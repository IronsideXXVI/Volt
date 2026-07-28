import AppKit
import SwiftUI

/// A small, restrained set of design tokens. The dashboard leans on native
/// materials, hairline dividers, and provider tints rather than gradients or
/// glows, so the interface stays quiet and legible in light and dark modes.
enum VoltTheme {
    /// Volt's one brand accent — used sparingly for usage bars, links outside
    /// notices, Save & Test, and active native controls.
    static let primary = Color(hex: "D94BC9")

    /// Neutral gray for the "time elapsed" comparison bar. Adaptive so it reads
    /// darker in light mode while staying visible against a dark background.
    static let windowElapsed = Color.primary.opacity(0.55)

    /// Subtle fills and lines, derived from the label color so they adapt to
    /// the current appearance automatically.
    static let track = Color.primary.opacity(0.08)
    static let hairline = Color.primary.opacity(0.09)
    static let card = Color.primary.opacity(0.035)
    static let cardHover = Color.primary.opacity(0.06)
}

extension AIProvider {
    var systemImage: String {
        switch self {
        case .anthropic:
            return "sparkle"
        case .openAI:
            return "brain"
        }
    }

    /// Volt uses a single brand accent everywhere rather than per-provider
    /// colors, so both providers resolve to the same magenta tint.
    var tint: Color {
        VoltTheme.primary
    }

    /// The provider's monochrome logo asset (a template image tinted to match
    /// the surrounding text color).
    var logoAsset: String {
        switch self {
        case .anthropic:
            return "ClaudeLogo"
        case .openAI:
            return "OpenAILogo"
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        switch cleaned.count {
        case 8:
            self.init(
                .sRGB,
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                opacity: Double(value & 0xFF) / 255
            )
        default:
            self.init(
                .sRGB,
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                opacity: 1
            )
        }
    }
}

enum VoltAssets {
    static let logo: NSImage = {
        guard let url = Bundle.main.url(forResource: "applogo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            assertionFailure("Missing bundled applogo.png")
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return image
    }()
}

struct VoltLogoView: View {
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: VoltAssets.logo)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Volt")
    }
}

/// A flat, tinted glyph — an SF Symbol on a low-opacity rounded square.
/// No gradients, borders, or shadows.
struct VoltGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// A concise section heading: a title with an optional trailing accessory.
struct SectionHeader<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .voltSectionHeader()
                if let detail {
                    Text(detail)
                        .voltCaption()
                }
            }
            Spacer(minLength: 8)
            accessory()
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String, detail: String? = nil) {
        self.init(title: title, detail: detail, accessory: { EmptyView() })
    }
}

/// The semantic meaning of an inline notice. Severity changes only the symbol
/// and VoiceOver prefix; every visual treatment remains neutral.
enum VoltNoticeKind {
    case information
    case success
    case warning
    case error

    fileprivate var symbol: String {
        switch self {
        case .information:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }

    fileprivate var accessibilityPrefix: String {
        switch self {
        case .information:
            return "Information"
        case .success:
            return "Success"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        }
    }
}

/// The single shared treatment for inline notices in both the drawer and
/// Settings. Its fill intentionally matches the unused portion of limit bars.
struct VoltNotice: View {
    let message: String
    let kind: VoltNoticeKind
    private let parsesMarkdown: Bool

    init(_ message: String, kind: VoltNoticeKind) {
        self.message = message
        self.kind = kind
        parsesMarkdown = true
    }

    /// Use for operational or provider error text that must be displayed
    /// literally rather than interpreted as Markdown.
    init(verbatim message: String, kind: VoltNoticeKind) {
        self.message = message
        self.kind = kind
        parsesMarkdown = false
    }

    private var markdown: AttributedString {
        var attributed: AttributedString
        if parsesMarkdown {
            attributed = (try? AttributedString(
                markdown: message,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(message)
        } else {
            attributed = AttributedString(message)
        }

        let linkRanges = attributed.runs
            .filter { $0.link != nil }
            .map(\.range)
        for range in linkRanges {
            attributed[range].foregroundColor = Color.secondary
            attributed[range].underlineStyle = .single
        }
        return attributed
    }

    private func noticeContent(_ attributed: AttributedString, exposesPrefix: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: kind.symbol)
                .font(.system(size: 11, weight: .medium))
                .padding(.top, 1)
                .accessibilityLabel(kind.accessibilityPrefix)
                .accessibilityHidden(!exposesPrefix)

            Text(attributed)
                .voltCaption()
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(VoltTheme.track)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(VoltTheme.hairline, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    var body: some View {
        let attributed = markdown
        let hasLinks = attributed.runs.contains { $0.link != nil }

        if hasLinks {
            noticeContent(attributed, exposesPrefix: true)
                .accessibilityElement(children: .contain)
        } else {
            noticeContent(attributed, exposesPrefix: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(kind.accessibilityPrefix), \(String(attributed.characters))"
                )
        }
    }
}

// MARK: - Text styles (one canonical style per field type)

extension View {
    /// The "<Provider> plan usage limits" heading.
    func voltTitle() -> some View { font(.system(size: 15, weight: .semibold)) }

    /// A section heading (Weekly limits, Usage, Usage credits, Spend limit…).
    func voltSectionHeader() -> some View { font(.system(size: 13, weight: .semibold)) }

    /// The heading of a full-view state (connect, error, empty, syncing).
    func voltStateTitle() -> some View { font(.system(size: 14, weight: .semibold)) }

    /// A usage-row's primary text: name, percentage, reset, and elapsed.
    func voltRowText() -> some View { font(.system(size: 12, weight: .semibold)).monospacedDigit() }

    /// A key/value detail row's value (e.g. "$0.00", "Off").
    func voltDetailValue() -> some View { font(.system(size: 11, weight: .semibold, design: .monospaced)) }

    /// Secondary descriptive text: account/plan lines, subtitles, notices,
    /// detail labels, and empty/edge messages.
    func voltCaption() -> some View { font(.system(size: 11)).foregroundStyle(.secondary) }

    /// The app wordmark in the top bar.
    func voltHeaderTitle() -> some View { font(.system(size: 13, weight: .semibold)) }

    /// A provider switcher tab label.
    func voltTabLabel(selected: Bool) -> some View {
        font(.system(size: 13, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? .primary : .secondary)
    }

    /// The footer status text + control glyphs.
    func voltFooterText() -> some View { font(.system(size: 12, weight: .medium)) }

    /// A settings control/row primary label — a provider name in a picker, a
    /// toggle's title, a key in a key/value row, a disclosure heading.
    func voltControlLabel() -> some View { font(.system(size: 12, weight: .semibold)) }

}
