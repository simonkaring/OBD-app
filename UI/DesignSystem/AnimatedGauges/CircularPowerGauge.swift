import SwiftUI

public struct CircularPowerGauge: View {
    public var powerKW: Double // -50 (Regen) to +150 (Power)
    public var maxPowerKW: Double = 150.0
    public var maxRegenKW: Double = 50.0

    private var normalizedProgress: Double {
        if powerKW >= 0 {
            return min(1.0, powerKW / maxPowerKW)
        } else {
            return max(-1.0, powerKW / maxRegenKW)
        }
    }

    public init(powerKW: Double) {
        self.powerKW = powerKW
    }

    public var body: some View {
        ZStack {
            // Background Arc Track
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(90))

            // Regen Arc (Counter-Clockwise Green Arc)
            if powerKW < 0 {
                Circle()
                    .trim(from: 0.5 + (normalizedProgress * 0.35), to: 0.5)
                    .stroke(
                        LinearGradient(colors: [Theme.regenGreen, Color.cyan], startPoint: .trailing, endPoint: .leading),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: powerKW)
            }

            // Positive Power Arc (Clockwise Cyan -> Amber Arc)
            if powerKW >= 0 {
                Circle()
                    .trim(from: 0.5, to: 0.5 + (normalizedProgress * 0.35))
                    .stroke(
                        LinearGradient(colors: [Theme.electricCyan, Theme.highPowerAmber, Theme.criticalRed], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: powerKW)
            }

            // Center Digital Telemetry Display
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", abs(powerKW)))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(powerKW < 0 ? Theme.regenGreen : Theme.textPrimary)
                    Text("kW")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                }

                Text(powerKW < -0.5 ? "REGEN BRAKING" : (powerKW > 5.0 ? "POWER DRAW" : "IDLE"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(powerKW < 0 ? Theme.regenGreen.opacity(0.2) : Theme.electricCyan.opacity(0.2))
                    .foregroundColor(powerKW < 0 ? Theme.regenGreen : Theme.electricCyan)
                    .cornerRadius(8)
            }
        }
        .padding(20)
    }
}
