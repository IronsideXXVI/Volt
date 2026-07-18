import AppKit
import SwiftUI

enum VoltTheme {
    static let primary = Color(hex: "FF00FF")
    static let alternate = Color(hex: "4C004A")
    static let electricBlue = Color(hex: "7B61FF")
    static let windowElapsed = Color(hex: "9090A4")

    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color.primary.opacity(0.035)
    static let surface = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let elevatedSurface = Color.primary.opacity(0.075)
    static let track = Color.primary.opacity(0.105)
    static let hairline = Color.primary.opacity(0.11)
    static let strongHairline = Color.primary.opacity(0.18)
    static let softShadow = Color.black.opacity(0.10)

    static let brandGradient = LinearGradient(
        colors: [primary, electricBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

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
            return Color(hex: "E97545")
        case .openAI:
            return Color(hex: "168BFF")
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [tint, tint.opacity(0.62)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

struct VoltBackdrop: View {
    var tint: Color = VoltTheme.primary

    var body: some View {
        ZStack {
            VoltTheme.canvas

            Circle()
                .fill(tint.opacity(0.09))
                .frame(width: 330, height: 330)
                .blur(radius: 80)
                .offset(x: 210, y: -210)

            Circle()
                .fill(VoltTheme.electricBlue.opacity(0.055))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -220, y: 260)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct VoltIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 40
    var symbolSize: CGFloat = 15

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.20), tint.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(tint.opacity(0.20), lineWidth: 0.75)
        }
    }
}

struct VoltStatusPill: View {
    let title: String
    let color: Color
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .bold))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.10), in: Capsule())
        .overlay {
            Capsule().strokeBorder(color.opacity(0.16), lineWidth: 0.5)
        }
    }
}

struct VoltSurface<Content: View>: View {
    var cornerRadius: CGFloat
    var padding: CGFloat
    var accent: Color?
    private let content: Content

    init(
        cornerRadius: CGFloat = 15,
        padding: CGFloat = 15,
        accent: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VoltTheme.surface)
                    .shadow(color: VoltTheme.softShadow, radius: 8, y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        accent?.opacity(0.20) ?? VoltTheme.hairline,
                        lineWidth: accent == nil ? 0.5 : 0.75
                    )
            }
    }
}

struct VoltSectionLabel: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
