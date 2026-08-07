import SwiftUI

public enum Theme {
    public static let backgroundDark = Color(red: 0.05, green: 0.07, blue: 0.10)
    public static let cardBackground = Color(red: 0.10, green: 0.13, blue: 0.18).opacity(0.7)
    
    public static let electricCyan = Color(red: 0.0, green: 0.94, blue: 1.0)
    public static let regenGreen = Color(red: 0.0, green: 0.90, blue: 0.46)
    public static let highPowerAmber = Color(red: 1.0, green: 0.57, blue: 0.0)
    public static let criticalRed = Color(red: 1.0, green: 0.23, blue: 0.19)
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.7)

    public static let powerGradient = LinearGradient(
        colors: [electricCyan, highPowerAmber, criticalRed],
        startPoint: .leading,
        endPoint: .trailing
    )

    public static let regenGradient = LinearGradient(
        colors: [Color.blue, regenGreen],
        startPoint: .leading,
        endPoint: .trailing
    )
}

public struct GlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 20

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Theme.cardBackground)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
    }
}

extension View {
    public func glassCard(cornerRadius: CGFloat = 20) -> some View {
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
