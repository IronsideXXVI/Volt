import AppKit
import SwiftUI

enum VoltTheme {
    static let primary = Color(hex: "FF00FF")
    static let alternate = Color(hex: "4C004A")
    static let track = Color.primary.opacity(0.10)
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
