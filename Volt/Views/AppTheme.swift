import AppKit
import SwiftUI

/// A small, restrained set of design tokens. The dashboard leans on native
/// materials, hairline dividers, and provider tints rather than gradients or
/// glows, so the interface stays quiet and legible in light and dark modes.
enum VoltTheme {
    /// Volt's brand accent — a refined magenta used sparingly for app-level
    /// (non-provider) emphasis such as the wordmark and General settings.
    static let primary = Color(hex: "D94BC9")
    static let electricBlue = Color(hex: "7B61FF")

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

/// A provider's monochrome logo on a low-opacity rounded square — the branded
/// counterpart to `VoltGlyph`, matching the logos shown in the popover switcher.
struct VoltLogoGlyph: View {
    let asset: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.5, height: size * 0.5)
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

    /// Emphatic small text inside a status pill or inline status label. The
    /// caller supplies the semantic color (primary / orange / green).
    func voltChipText() -> some View { font(.system(size: 11, weight: .semibold)) }
}

extension View {
    /// A quiet card: subtle fill, hairline border, continuous corners.
    func voltCard(cornerRadius: CGFloat = 12, padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VoltTheme.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(VoltTheme.hairline, lineWidth: 0.5)
            }
    }
}
