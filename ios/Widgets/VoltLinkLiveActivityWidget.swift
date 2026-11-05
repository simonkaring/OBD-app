#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit

struct VoltLinkLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoltLinkActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Label(
                            state.mode == .charging ? "Charging" : "Trip",
                            systemImage: state.mode == .charging ? "bolt.fill" : "road.lanes"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(activityAccent(for: state.mode))
                        if state.isDemoMode { DemoBadge() }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Int(state.socPct.rounded()))%")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(activityAccent(for: state.mode))
                        Text(secondaryMetric(for: state))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.vehicleName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedStatsRow(state: state)
                }
            } compactLeading: {
                Image(systemName: state.mode == .charging ? "bolt.fill" : "car.side")
                    .foregroundStyle(activityAccent(for: state.mode))
            } compactTrailing: {
                // The elapsed clock animates itself, so it costs no ActivityKit updates and
                // is the only second value that fits here. Speed would fit too, but then
                // state of charge disappears from the compact presentation.
                Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: state.mode == .charging ? "bolt.fill" : "car.side")
                    .foregroundStyle(activityAccent(for: state.mode))
            }
            .keylineTint(activityAccent(for: state.mode))
        }
    }

    /// Speed while driving, charge power while plugged in: the value the expanded
    /// trailing region shows under the state of charge.
    private func secondaryMetric(for state: VoltLinkActivityContent) -> String {
        let units = state.units
        return state.mode == .charging
            ? units.activityPower(kilowatts: state.powerKW)
            : "\(units.activitySpeed(kilometersPerHour: state.speedKmH)) \(units.speedSymbol)"
    }
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<VoltLinkActivityAttributes>

    private var state: VoltLinkActivityContent { context.state }
    private var units: SharedDisplayUnits { state.units }

    var body: some View {
        HStack(spacing: 14) {
            Gauge(value: min(100, max(0, state.socPct)), in: 0...100) {
                Image(systemName: state.mode == .charging ? "bolt.fill" : "car.side")
            } currentValueLabel: {
                Text("\(Int(state.socPct.rounded()))")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(activityAccent(for: state.mode))
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(context.attributes.vehicleName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if state.isDemoMode { DemoBadge() }
                }
                // Long vehicle names and miles push the line wider than a small phone's
                // card, so drop the unit symbols before letting it truncate.
                ViewThatFits(in: .horizontal) {
                    statsLine(short: false)
                    statsLine(short: true)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 0) {
                Text(primaryMetric(for: state))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(state.mode == .charging ? units.powerSymbol : units.speedSymbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private func primaryMetric(for state: VoltLinkActivityContent) -> String {
        state.mode == .charging
            ? String(Int(units.power(kilowatts: state.powerKW).rounded()))
            : units.activitySpeed(kilometersPerHour: state.speedKmH)
    }

    private func statsLine(short: Bool) -> some View {
        HStack(spacing: 6) {
            if state.mode == .trip {
                LabelCell(icon: "road.lanes", text: units.activityRange(kilometers: state.rangeKm, short: short))
                LabelCell(
                    icon: "leaf.fill",
                    text: units.activityConsumption(
                        kilowattHoursPer100Kilometers: state.averageConsumptionKWhPer100Km, short: short))
            }
            ElapsedCell(startedAt: state.startedAt)
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct ExpandedStatsRow: View {
    let state: VoltLinkActivityContent

    private var units: SharedDisplayUnits { state.units }

    var body: some View {
        HStack(spacing: 12) {
            if state.mode == .trip {
                LabelCell(icon: "road.lanes", text: units.activityRange(kilometers: state.rangeKm))
                LabelCell(
                    icon: "leaf.fill",
                    text: units.activityConsumption(kilowattHoursPer100Kilometers: state.averageConsumptionKWhPer100Km))
            } else {
                LabelCell(icon: "bolt.fill", text: units.activityPower(kilowatts: state.powerKW))
            }
            ElapsedCell(startedAt: state.startedAt)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct LabelCell: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

private struct ElapsedCell: View {
    let startedAt: Date

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
            Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        }
    }
}

private func activityAccent(for mode: VoltLinkActivityContent.Mode) -> Color {
    mode == .charging ? .green : .cyan
}

private extension SharedDisplayUnits {
    /// Estimated range, or `--` when the app has no estimate for the current SoC.
    func activityRange(kilometers: Double?, short: Bool = false) -> String {
        guard let kilometers, kilometers.isFinite, kilometers > 0 else { return "--" }
        let value = Int(distance(kilometers: kilometers).rounded())
        return short ? "\(value) \(distanceSymbol)" : "≈ \(value) \(distanceSymbol)"
    }

    /// `--` until the trip is long enough and power data is complete, never a zero sentinel.
    func activityConsumption(kilowattHoursPer100Kilometers value: Double?, short: Bool = false) -> String {
        guard let value, value.isFinite else { return "--" }
        let converted = String(format: "%.1f", efficiency(kilowattHoursPer100Kilometers: value))
        return short ? "Ø \(converted)" : "Ø \(converted) \(efficiencySymbol)"
    }

    func activitySpeed(kilometersPerHour speed: Double) -> String {
        guard speed.isFinite else { return "--" }
        return String(Int(self.speed(kilometersPerHour: speed).rounded()))
    }

    func activityPower(kilowatts: Double) -> String {
        guard kilowatts.isFinite else { return "--" }
        return "\(Int(power(kilowatts: kilowatts).rounded())) \(powerSymbol)"
    }
}
#endif
