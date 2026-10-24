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
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.highPowerAmber)

            VStack(alignment: .leading, spacing: 1) {
                Text("OBD Scanner Disconnected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Tap to connect BLE scanner or set up vehicle")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 8)

            Button(action: onConnectTap) {
                Text("Connect")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.electricCyan)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            Button(action: onDismissTap) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Warning")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
