import SwiftUI

public struct FloatingConnectionBanner: View {
    public var onConnectTap: () -> Void
    public var onDismissTap: () -> Void

    public init(onConnectTap: @escaping () -> Void, onDismissTap: @escaping () -> Void) {
        self.onConnectTap = onConnectTap
        self.onDismissTap = onDismissTap
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Theme.highPowerAmber)

            VStack(alignment: .leading, spacing: 1) {
                Text("OBD Scanner Disconnected")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)

                Text("Tap to connect BLE scanner or set up vehicle")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer(minLength: 8)

            Button(action: onConnectTap) {
                Text("Connect")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.electricCyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Theme.electricCyan.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: onDismissTap) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Warning")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Theme.cardBackground)
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Theme.highPowerAmber.opacity(0.4), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#Preview("Floating Connection Banner") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            FloatingConnectionBanner(onConnectTap: {}, onDismissTap: {})
            Spacer()
        }
    }
}
