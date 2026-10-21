import SwiftUI

public struct HUDModeView: View {
    public var speedKmH: Double
    public var powerKW: Double
    public var socPct: Double?
    public var isDemoMode: Bool = false
    @Binding public var isPresented: Bool

    /// HUD numerals scale with Dynamic Type instead of staying fixed at 110/40 pt.
    @ScaledMetric(relativeTo: .largeTitle) private var speedFontSize: CGFloat = 110
    @ScaledMetric(relativeTo: .title) private var metricFontSize: CGFloat = 40

    public var body: some View {
        ZStack {
            Theme.backgroundDark.ignoresSafeArea()

            VStack(spacing: 30) {
                HStack {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Exit heads-up display")
                    Spacer()
                    if isDemoMode {
                        Text("SIMULATED")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.highPowerAmber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.highPowerAmber.opacity(0.15))
                            .cornerRadius(4)
                    }
                    Text("HEAD-UP DISPLAY MODE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.electricCyan)
                }
                .padding()

                Spacer()

                VStack(spacing: 10) {
                    Text(String(format: "%.0f", speedKmH))
                        .font(.system(size: speedFontSize, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.regenGreen)

                    Text("KM/H")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.textPrimary)
                }

                HStack(spacing: 40) {
                    VStack {
                        Text(socPct.map { "\(Int($0))%" } ?? "--%")
                            .font(.system(size: metricFontSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.electricCyan)
                        Text("BATTERY")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack {
                        Text(String(format: "%.1f kW", powerKW))
                            .font(.system(size: metricFontSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(powerKW < 0 ? Theme.regenGreen : Theme.highPowerAmber)
                        Text("POWER")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()

                Text("Reflect off windshield at night")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 20)
            }
            .scaleEffect(x: -1, y: 1)  // Mirror display horizontally for windshield reflection
        }
    }
}

#Preview("HUD Mode View") {
    HUDModeView(
        speedKmH: 88,
        powerKW: 24.5,
        socPct: 76,
        isPresented: .constant(true)
    )
}
