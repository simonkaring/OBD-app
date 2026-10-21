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
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(
                        context.state.mode == .charging ? "Charging" : "Trip",
                        systemImage: context.state.mode == .charging ? "bolt.fill" : "road.lanes"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.state.mode == .charging ? .green : .cyan)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.socPct.rounded()))%")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.vehicleName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 16) {
                        if context.state.mode == .charging {
                            Label("\(Int(context.state.powerKW.rounded())) kW", systemImage: "bolt")
                            Label("Since \(context.state.startedAt.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                        } else {
                            Label("\(Int(context.state.speedKmH.rounded())) km/h", systemImage: "speedometer")
                            Label("\(String(format: "%.1f", context.state.distanceKm)) km", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        Spacer()
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: context.state.mode == .charging ? "bolt.fill" : "car.side")
                    .foregroundStyle(context.state.mode == .charging ? .green : .cyan)
            } compactTrailing: {
                Text("\(Int(context.state.socPct.rounded()))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.mode == .charging ? "bolt.fill" : "car.side")
                    .foregroundStyle(context.state.mode == .charging ? .green : .cyan)
            }
            .keylineTint(.cyan)
        }
    }
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<VoltLinkActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Gauge(value: min(100, max(0, context.state.socPct)), in: 0...100) {
                Image(systemName: context.state.mode == .charging ? "bolt.fill" : "car.side")
            } currentValueLabel: {
                Text("\(Int(context.state.socPct.rounded()))")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(context.state.mode == .charging ? .green : .cyan)
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.vehicleName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if context.state.mode == .charging {
                    Text("\(Int(context.state.powerKW.rounded())) kW · charging")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(Int(context.state.speedKmH.rounded())) km/h · \(String(format: "%.1f", context.state.distanceKm)) km")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(Int(context.state.socPct.rounded()))%")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(context.state.mode == .charging ? .green : .cyan)
        }
        .padding(14)
    }
}
#endif
