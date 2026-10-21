import SwiftUI

public struct BatteryLevelBar: View {
    public var socPct: Double?
    public var batteryTempC: Double?
    public var isCharging: Bool
    /// Battery level when the active charging session began, drawn as a tick on the bar.
    public var startSocPct: Double?

    public init(socPct: Double?, batteryTempC: Double? = nil, isCharging: Bool = false, startSocPct: Double? = nil) {
        self.socPct = socPct
        self.batteryTempC = batteryTempC
        self.isCharging = isCharging
        self.startSocPct = startSocPct
    }

    private var socGainedPct: Double? {
        guard let socPct, let startSocPct else { return nil }
        let gained = socPct - startSocPct
        return gained >= 0.5 ? gained : nil
    }

    private var barColor: Color {
        guard let socPct else { return Theme.textSecondary }
        if isCharging { return Theme.regenGreen }
        if socPct < 20.0 { return Theme.criticalRed }
        if socPct < 40.0 { return Theme.highPowerAmber }
        return Theme.gaugeCyan
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text("High Voltage Battery")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                } icon: {
                    Image(systemName: isCharging ? "bolt.batteryblock.fill" : "batteryblock.fill")
                        .foregroundStyle(barColor)
                }

                Spacer()

                if let batteryTempC {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.medium")
                            .foregroundStyle(batteryTempC > 38.0 ? Theme.criticalRed : Theme.textSecondary)
                        Text(String(format: "HV: %.1f°C", batteryTempC))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }

            HStack(spacing: 8) {
                ProgressView(value: min(100, max(0, socPct ?? 0)), total: 100)
                    .progressViewStyle(TelemetryBarStyle(color: barColor))
                    .overlay {
                        if let startSocPct {
                            StartSOCMarker(fraction: min(1, max(0, startSocPct / 100)))
                        }
                    }

                Text(socPct.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize()
            }

            if let startSocPct {
                HStack(spacing: 6) {
                    Capsule()
                        .fill(Theme.textPrimary)
                        .frame(width: 3, height: 10)
                    Text(String(format: "Charging started at %.0f%%", startSocPct))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    if let socGainedPct {
                        Text(String(format: "+%.0f%% gained", socGainedPct))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.regenGreen)
                    }
                }
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
        let started = startSocPct.map { String(format: ", started charging at %.0f percent", $0) } ?? ""
        return String(format: "%.0f percent", socPct) + temperature + started + (isCharging ? ", charging" : "")
    }
}

/// Tick drawn on the filled bar at the level where the current charge began.
private struct StartSOCMarker: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            let markerHeight = max(8, geometry.size.height - 4)
            let halfMarkerWidth: CGFloat = 2.5
            let x = min(
                max(geometry.size.width * fraction, halfMarkerWidth),
                max(halfMarkerWidth, geometry.size.width - halfMarkerWidth))
            ZStack {
                Capsule().fill(Theme.backgroundDark).frame(width: 5, height: markerHeight)
                Capsule().fill(Theme.textPrimary).frame(width: 3, height: markerHeight)
            }
            .position(x: x, y: geometry.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
