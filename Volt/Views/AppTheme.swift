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

    /// Neutral gray for the "time elapsed" comparison bar. Reads in both modes.
    static let windowElapsed = Color(hex: "9A9AA8")

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

    /// The single accent used for a provider's rows, bars, and controls.
    var tint: Color {
        switch self {
        case .anthropic:
            return Color(hex: "E97545")
        case .openAI:
            return Color(hex: "168BFF")
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
                    .font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
