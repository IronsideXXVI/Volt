import AppKit
import SwiftUI

enum VoltTheme {
    static let primary = Color(hex: "FF00FF")
    static let alternate = Color(hex: "4C004A")
    static let windowElapsed = Color(hex: "9898AA")

    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color.primary.opacity(0.028)
    static let surface = Color.primary.opacity(0.045)
    static let elevatedSurface = Color.primary.opacity(0.065)
    static let track = Color.primary.opacity(0.105)
    static let hairline = Color.primary.opacity(0.12)
    static let strongHairline = Color.primary.opacity(0.18)

    // Retained for views that predate the surface naming.
    static let panel = surface
}

extension AIProvider {
    var systemImage: String {
        switch self {
        case .anthropic:
            return "sparkles"
        case .openAI:
            return "brain.head.profile"
        }
    }

    var tint: Color {
        switch self {
        case .anthropic:
            return Color(hex: "E56B3F")
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
    var size: CGFloat = 30

    var body: some View {
        Image(nsImage: VoltAssets.logo)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Volt")
    }
}

struct VoltSurface<Content: View>: View {
    var cornerRadius: CGFloat = 13
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VoltTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(VoltTheme.hairline, lineWidth: 0.5)
            }
    }
}
