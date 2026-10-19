import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    static let bg = Color(hex: 0x0d0f0e)
    static let surface = Color(hex: 0x1e231e)
    static let border = Color(hex: 0xa0b9a0, opacity: 0.12)
    static let text = Color(hex: 0xd4dfd4)
    static let text2 = Color(hex: 0x8a9e8a)
    static let text3 = Color(hex: 0x5a6b5a)
    static let accent = Color(hex: 0x7aad7a)
    static let accent2 = Color(hex: 0xa8c8a8)
    static let danger = Color(hex: 0xc87a7a)
    static let weekAvg = Color(hex: 0xd0aa6e)

    static let serifName = "CormorantGaramond-Light"
    static let serifItalicName = "CormorantGaramond-LightItalic"

    static func serif(_ size: CGFloat) -> Font { .custom(serifName, fixedSize: size) }
    static func serifItalic(_ size: CGFloat) -> Font { .custom(serifItalicName, fixedSize: size) }
    static func ui(_ size: CGFloat) -> Font { .system(size: size, weight: .light) }
}

/// Мелкая подпись: системный light, uppercase, трекинг.
struct CapsLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = Theme.text3
    var tracking: CGFloat = 0.14

    init(_ text: String, size: CGFloat = 10, color: Color = Theme.text3, tracking: CGFloat = 0.14) {
        self.text = text; self.size = size; self.color = color; self.tracking = tracking
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.ui(size))
            .tracking(size * tracking)
            .foregroundStyle(color)
    }
}

struct CardBackground: ViewModifier {
    var radius: CGFloat = 12
    var borderColor: Color = Theme.border
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(borderColor, lineWidth: 1))
    }
}

extension View {
    func card(radius: CGFloat = 12, border: Color = Theme.border) -> some View {
        modifier(CardBackground(radius: radius, borderColor: border))
    }
}

enum Formatters {
    static let dayLine: DateFormatter = make("EEE, d MMM")
    static let dayLineYear: DateFormatter = make("EEE, d MMM yyyy")
    static let time: DateFormatter = make("HH:mm")
    static let month: DateFormatter = make("MMM yyyy")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
