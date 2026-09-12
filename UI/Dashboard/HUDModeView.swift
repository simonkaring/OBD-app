import SwiftUI

public struct HUDModeView: View {
    public var speedKmH: Double
    public var powerKW: Double
    public var socPct: Double?
    @Binding public var isPresented: Bool

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
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Text("HEAD-UP DISPLAY MODE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.electricCyan)
                }
                .padding()

                Spacer()

                VStack(spacing: 10) {
                    Text(String(format: "%.0f", speedKmH))
                        .font(.system(size: 110, weight: .black, design: .rounded))
                        .foregroundColor(Theme.regenGreen)

                    Text("KM/H")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.textPrimary)
                }

                HStack(spacing: 40) {
                    VStack {
                        Text(socPct.map { "\(Int($0))%" } ?? "--%")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.electricCyan)
                        Text("BATTERY")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }

                    VStack {
                        Text(String(format: "%.1f kW", powerKW))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(powerKW < 0 ? Theme.regenGreen : Theme.highPowerAmber)
                        Text("POWER")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                Spacer()

                Text("Reflect off windshield at night")
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.bottom, 20)
            }
            .scaleEffect(x: -1, y: 1) // Mirror display horizontally for windshield reflection
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
