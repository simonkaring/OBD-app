import SwiftUI

public struct SpeedometerView: View {
    public var speedKmH: Double

    public init(speedKmH: Double) {
        self.speedKmH = speedKmH
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.0f", speedKmH))
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .contentTransition(.numericText())

            Text("KM / H")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.electricCyan)
                .tracking(2)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 28)
        .glassCard()
    }
}
