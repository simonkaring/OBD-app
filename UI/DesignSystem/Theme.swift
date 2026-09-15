import SwiftUI

public enum Theme {
    #if os(iOS)
    public static let backgroundDark = Color(uiColor: UIColor.systemGroupedBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
    public static let cardBackground = Color(uiColor: UIColor.secondarySystemGroupedBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
    #else
    public static let backgroundDark = Color(white: 0.0)
    public static let cardBackground = Color(white: 0.11)
    #endif
    
    public static let electricCyan = Color.blue
    public static let regenGreen = Color.green
    public static let highPowerAmber = Color.orange
    public static let criticalRed = Color.red
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.7)

    /// Hairline separators over the dark background.
    public static let divider = Color.white.opacity(0.15)
    /// Legible text/icon color drawn on top of an accent-colored fill.
    public static let onAccent = Color.black
    /// Unfilled track color behind dial/bar gauges.
    public static let trackBackground = Color.white.opacity(0.1)

    public static let powerGradient = LinearGradient(
        colors: [textPrimary, textPrimary],
        startPoint: .leading,
        endPoint: .trailing
    )

    public static let regenGradient = LinearGradient(
        colors: [regenGreen, regenGreen],
        startPoint: .leading,
        endPoint: .trailing
    )

    public static let speedGradient = LinearGradient(
        colors: [textPrimary, textPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let socGradient = LinearGradient(
        colors: [regenGreen, regenGreen],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let socLowGradient = LinearGradient(
        colors: [highPowerAmber, highPowerAmber],
        startPoint: .leading,
        endPoint: .trailing
    )
}

public struct GlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 16

    public func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    public func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    public func inlineTitleDisplayMode() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
