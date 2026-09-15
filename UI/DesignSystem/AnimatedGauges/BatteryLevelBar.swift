import SwiftUI

public struct BatteryLevelBar: View {
    public var socPct: Double?
    public var batteryTempC: Double?
    public var isCharging: Bool

    public init(socPct: Double?, batteryTempC: Double? = nil, isCharging: Bool = false) {
        self.socPct = socPct
        self.batteryTempC = batteryTempC
        self.isCharging = isCharging
    }

    private var barColor: Color {
        guard let socPct else { return Theme.textSecondary }
        if isCharging { return Theme.regenGreen }
        if socPct < 20.0 { return Theme.criticalRed }
        if socPct < 40.0 { return Theme.highPowerAmber }
        return Theme.regenGreen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text("High Voltage Battery")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                } icon: {
                    Image(systemName: isCharging ? "bolt.batteryblock.fill" : "batteryblock.fill")
                        .foregroundColor(barColor)
                }

                Spacer()

                if let batteryTempC {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.medium")
                            .foregroundColor(batteryTempC > 38.0 ? Theme.criticalRed : Theme.textSecondary)
                        Text(String(format: "HV: %.1f°C", batteryTempC))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                    }
                }
            }

            HStack(spacing: 8) {
                ProgressView(value: min(100, max(0, socPct ?? 0)), total: 100)
                    .tint(barColor)

                Text(socPct.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundColor(Theme.textPrimary)
                    .fixedSize()
            }
        }
        .padding(16)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("High Voltage Battery")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let socPct else { return "Unavailable" }
        let temperature = batteryTempC.map { String(format: ", %.1f degrees Celsius", $0) } ?? ""
        return String(format: "%.0f percent", socPct) + temperature + (isCharging ? ", charging" : "")
    }
}
