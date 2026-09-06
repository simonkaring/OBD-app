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
        return Theme.electricCyan
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text("High Voltage Battery")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                } icon: {
                    Image(systemName: isCharging ? "bolt.batteryblock.fill" : "batteryblock.fill")
                        .foregroundColor(barColor)
                }

                Spacer()

                if let batteryTempC {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.medium")
                            .foregroundColor(batteryTempC > 38.0 ? Theme.criticalRed : Theme.electricCyan)
                        Text(String(format: "HV: %.1f°C", batteryTempC))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.textPrimary)
                    }
                }
            }

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.trackBackground)
                            .frame(height: 20)

                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [barColor.opacity(0.7), barColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, min(geo.size.width, geo.size.width * ((socPct ?? 0) / 100.0))), height: 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: socPct)
                    }
                }
                .frame(height: 20)

                Text(socPct.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                    .frame(width: 50, alignment: .trailing)
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
