import SwiftUI

struct BaumioTheme {
    static let background = Color(hex: "0F1117")
    static let surface = Color(hex: "171B24")
    static let elevatedSurface = Color(hex: "1D2330")
    static let border = Color(hex: "252D3D")
    static let accent = Color(hex: "F59E0B")
    static let accentSecondary = Color(hex: "FF6B35")
    static let success = Color(hex: "22C55E")
    static let warning = Color(hex: "F59E0B")
    static let danger = Color(hex: "EF4444")
    static let info = Color(hex: "3B82F6")
    static let primaryText = Color(hex: "F8FAFC")
    static let secondaryText = Color(hex: "94A3B8")

    static let cardRadius: CGFloat = 8
    static let controlRadius: CGFloat = 8
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red, green, blue, alpha: UInt64

        switch hex.count {
        case 3:
            (red, green, blue, alpha) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6:
            (red, green, blue, alpha) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (red, green, blue, alpha) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (red, green, blue, alpha) = (255, 255, 255, 255)
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

struct BaumioBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(BaumioTheme.background.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func baumioBackground() -> some View {
        modifier(BaumioBackground())
    }
}
