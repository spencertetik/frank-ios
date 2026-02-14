import SwiftUI

/// Centralized theme system for Frank iOS app
struct Theme {
    // MARK: - Colors
    
    /// Primary accent color - configurable
    static var accent: Color {
        AccentColorManager.currentColor
    }
    
    /// Dark glassy background colors (matching web dashboard)
    static let bgPrimary = Color(red: 0.047, green: 0.055, blue: 0.086)    // #0c0e16
    static let bgSecondary = Color(red: 0.075, green: 0.094, blue: 0.161)  // #131829
    static let bgCard = Color.white.opacity(0.04)
    static let borderCard = Color.white.opacity(0.08)
    static let accentIndigo = Color(red: 0.506, green: 0.596, blue: 1.0)   // indigo-400
    
    /// Legacy aliases
    static let background = bgPrimary
    static let cardBackground = bgSecondary
    static let groupedBackground = bgPrimary
    
    /// Text colors
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    static let textTertiary = Color.white.opacity(0.4)
    
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
    /// Apply glass card styling (dark glassy theme)
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    /// Apply standard card styling
    func cardStyle() -> some View {
        self
            .glassCard(cornerRadius: Theme.cornerRadiusMedium)
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
