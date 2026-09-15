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
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)

                Text("Tap to connect BLE scanner or set up vehicle")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer(minLength: 8)

            Button(action: onConnectTap) {
                Text("Connect")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.electricCyan)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            Button(action: onDismissTap) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
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
