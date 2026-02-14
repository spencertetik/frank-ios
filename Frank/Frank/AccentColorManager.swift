import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Handles persistence and presentation of the app's accent color.
enum AccentColorManager {
    static let storageKey = "accentColor"
    static let defaultHex = "#FF7A18"
    static let defaultColor = Color(red: 1.0, green: 0.48, blue: 0.09) // Vibrant orange
    
    static var currentHex: String {
        UserDefaults.standard.string(forKey: storageKey) ?? defaultHex
    }
    
    static var currentColor: Color {
        Color(hex: currentHex) ?? defaultColor
    }
    
    static func color(from hex: String) -> Color {
        Color(hex: hex) ?? defaultColor
    }
}

struct AccentColorOption: Identifiable, Hashable {
    let name: String
    let hex: String
    
    var id: String { hex }
    var color: Color { AccentColorManager.color(from: hex) }
    
    static let presets: [AccentColorOption] = [
        AccentColorOption(name: "Orange", hex: "#FF7A18"),
        AccentColorOption(name: "Blue", hex: "#0A84FF"),
        AccentColorOption(name: "Red", hex: "#FF453A"),
        AccentColorOption(name: "Green", hex: "#30D158"),
        AccentColorOption(name: "Purple", hex: "#BF5AF2"),
        AccentColorOption(name: "Pink", hex: "#FF2D55"),
        AccentColorOption(name: "Teal", hex: "#4DD0E1"),
        AccentColorOption(name: "Yellow", hex: "#FFD60A"),
        AccentColorOption(name: "Indigo", hex: "#5E5CE6"),
        AccentColorOption(name: "Mint", hex: "#66D4CF")
    ]
}

extension Color {
    /// Initialize a Color from a hex string (e.g. "#FFAA00" or "FFAA00").
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        let divisor = 255.0
        let red, green, blue, alpha: Double
        if cleaned.count == 6 {
            red = Double((value & 0xFF0000) >> 16) / divisor
            green = Double((value & 0x00FF00) >> 8) / divisor
            blue = Double(value & 0x0000FF) / divisor
            alpha = 1.0
        } else {
            red = Double((value & 0xFF000000) >> 24) / divisor
            green = Double((value & 0x00FF0000) >> 16) / divisor
            blue = Double((value & 0x0000FF00) >> 8) / divisor
            alpha = Double(value & 0x000000FF) / divisor
        }
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
    
    /// Hex string representation of the color (without alpha by default).
    func hexString(includeAlpha: Bool = false) -> String? {
        #if canImport(UIKit)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        if includeAlpha {
            return String(format: "#%02lX%02lX%02lX%02lX", lroundf(Float(red * 255)), lroundf(Float(green * 255)), lroundf(Float(blue * 255)), lroundf(Float(alpha * 255)))
        } else {
            return String(format: "#%02lX%02lX%02lX", lroundf(Float(red * 255)), lroundf(Float(green * 255)), lroundf(Float(blue * 255)))
        }
        #else
        return nil
        #endif
    }
}
