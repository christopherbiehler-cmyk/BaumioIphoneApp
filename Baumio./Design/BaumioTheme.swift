import SwiftUI
import UIKit

struct BaumioTheme {
    // Jede Farbe hat eine helle und eine dunkle Variante und folgt dem aktiven Farbschema.
    static let background = Color(light: "F3F5F9", dark: "0F1117")
    static let surface = Color(light: "FFFFFF", dark: "171B24")
    static let elevatedSurface = Color(light: "E9EDF4", dark: "1D2330")
    static let border = Color(light: "D3D9E4", dark: "252D3D")
    static let accent = Color(light: "B45309", dark: "F59E0B")
    static let accentSecondary = Color(light: "C2410C", dark: "FF6B35")
    static let success = Color(light: "15803D", dark: "22C55E")
    static let warning = Color(light: "B45309", dark: "F59E0B")
    static let danger = Color(light: "DC2626", dark: "EF4444")
    static let info = Color(light: "2563EB", dark: "3B82F6")
    static let primaryText = Color(light: "0F172A", dark: "F8FAFC")
    static let secondaryText = Color(light: "55637A", dark: "94A3B8")

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

    /// Farbe, die je nach Farbschema (hell/dunkel) zwischen zwei Hex-Werten wechselt.
    init(light: String, dark: String) {
        let lightColor = UIColor(Color(hex: light))
        let darkColor = UIColor(Color(hex: dark))
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }
}

/// Wendet den in den Einstellungen gewählten Darstellungsmodus an (Standard: Dunkel).
struct AppearanceModifier: ViewModifier {
    @AppStorage("appearanceMode") private var modeRaw = AppearanceMode.dark.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme((AppearanceMode(rawValue: modeRaw) ?? .dark).colorScheme)
    }
}

struct BaumioBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(BaumioTheme.background.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .modifier(AppearanceModifier())
    }
}

extension View {
    func baumioBackground() -> some View {
        modifier(BaumioBackground())
    }

    func appAppearance() -> some View {
        modifier(AppearanceModifier())
    }

    /// Einheitlicher Bestätigungsdialog für destruktive Aktionen.
    func deleteConfirmation<Item: Identifiable>(
        _ title: String,
        item: Binding<Item?>,
        message: @escaping (Item) -> String,
        onConfirm: @escaping (Item) -> Void
    ) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            presenting: item.wrappedValue
        ) { value in
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { onConfirm(value) }
        } message: { value in
            Text(message(value))
        }
    }
}
