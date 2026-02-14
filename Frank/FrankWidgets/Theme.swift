import SwiftUI

/// Widget-specific accent color helper
private enum WidgetAccentColorManager {
    static let storageKey = "accentColor"
    static let defaultHex = "#FF7A18"
    static let defaultColor = Color(red: 1.0, green: 0.48, blue: 0.09)
    
    static var currentHex: String {
        UserDefaults.standard.string(forKey: storageKey) ?? defaultHex
    }
    
    static var currentColor: Color {
        Color(hex: currentHex) ?? defaultColor
    }
}

private extension Color {
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
}

/// Centralized theme system for Frank iOS app
struct Theme {
    // MARK: - Colors
    
    /// Primary accent color - configurable
    static var accent: Color { WidgetAccentColorManager.currentColor }
    
    /// Background colors for light/dark mode
    static let background = Color(.systemBackground)
    static let cardBackground = Color(.secondarySystemBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    
    /// Text colors
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
    
    /// Status colors
    static let success = Color.green
    static let warning = Color.yellow
    static let error = Color.red
    static let disconnected = Color.red
    
    // MARK: - Typography
    
    static let titleFont = Font.largeTitle.weight(.bold)
    static let headlineFont = Font.headline.weight(.semibold)
    static let bodyFont = Font.body
    static let captionFont = Font.caption
    static let footnoteFont = Font.footnote
    
    // MARK: - Spacing
    
    static let paddingTiny: CGFloat = 4
    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 12
    static let paddingLarge: CGFloat = 16
    static let paddingXLarge: CGFloat = 20
    static let paddingXXLarge: CGFloat = 24
    
    // MARK: - Corner Radius
    
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 16
    
    // MARK: - Shadows
    
    static let cardShadow = Shadow(
        color: Color.black.opacity(0.1),
        radius: 4,
        x: 0,
        y: 2
    )
    
    // MARK: - Materials
    
    static let cardMaterial = Material.thinMaterial
    static let bannerMaterial = Material.regularMaterial
}

// MARK: - Shadow Helper

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extensions

extension View {
    /// Apply standard card styling
    func cardStyle() -> some View {
        self
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
            .shadow(
                color: Theme.cardShadow.color,
                radius: Theme.cardShadow.radius,
                x: Theme.cardShadow.x,
                y: Theme.cardShadow.y
            )
    }
    
    /// Apply material card styling (for widgets)
    func materialCardStyle() -> some View {
        self
            .background(Theme.cardMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
    }
    
    /// Apply standard button styling
    func buttonStyle(isProminent: Bool = false) -> some View {
        self
            .foregroundColor(isProminent ? .white : Theme.accent)
            .padding(.horizontal, Theme.paddingMedium)
            .padding(.vertical, Theme.paddingSmall)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                    .fill(isProminent ? Theme.accent : Theme.cardBackground)
            )
    }
}