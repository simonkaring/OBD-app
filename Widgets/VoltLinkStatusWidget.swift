import SwiftUI
import WidgetKit

struct SharedSnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedTelemetrySnapshot?
}

struct SharedSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SharedSnapshotEntry {
        SharedSnapshotEntry(
            date: Date(),
            snapshot: SharedTelemetrySnapshot(
                vehicleName: "Mercedes-Benz EQA 250", socPct: 68, powerKW: 42, speedKmH: 0, rangeKm: 312, isCharging: true, isConnected: true)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SharedSnapshotEntry) -> Void) {
        completion(SharedSnapshotEntry(date: Date(), snapshot: SharedTelemetryStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SharedSnapshotEntry>) -> Void) {
        let entry = SharedSnapshotEntry(date: Date(), snapshot: SharedTelemetryStore.load())
        // The app reloads timelines when telemetry meaningfully changes; this refresh
        // keeps a stale snapshot from claiming to be live.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct VoltLinkStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VoltLinkStatusWidget", provider: SharedSnapshotProvider()) { entry in
            VoltLinkStatusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.black
                }
        }
        .configurationDisplayName("Battery & Charging")
        .description("State of charge, estimated range, and charging power.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private struct VoltLinkStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SharedSnapshotEntry

    private var snapshot: SharedTelemetrySnapshot? { entry.snapshot }

    private var soc: Double { snapshot?.socPct ?? 0 }
    private var accent: Color { soc < 20 ? .red : (snapshot?.isCharging == true ? .green : .cyan) }

    var body: some View {
        if let snapshot {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(100, max(0, soc)), in: 0...100) {
                    Image(systemName: snapshot.isCharging ? "bolt.fill" : "battery.75")
                } currentValueLabel: {
                    Text("\(Int(soc.rounded()))%")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(accent)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.vehicleName)
                        .font(.caption2)
                    Text("\(Int(soc.rounded()))% · \(Int((snapshot.rangeKm ?? 0).rounded())) km")
                        .font(.headline)
                    Text(snapshot.isCharging ? "Charging \(Int(snapshot.powerKW.rounded())) kW" : (snapshot.isConnected ? "Connected" : "Disconnected"))
                        .font(.caption2)
                }
            default:
                content(for: snapshot)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "car.side")
                    .font(.title2)
                Text("Open VoltLink to connect")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(for snapshot: SharedTelemetrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BATTERY")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if snapshot.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(snapshot.socPct.rounded()))")
                    .font(.system(size: family == .systemSmall ? 44 : 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                Text("%")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let range = snapshot.rangeKm, range > 0 {
                Text("≈ \(Int(range.rounded())) km")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(snapshot.isConnected ? "Live" : "No connection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if family != .systemSmall {
                Divider()
                HStack(spacing: 12) {
                    Label(
                        snapshot.isCharging ? "\(Int(snapshot.powerKW.rounded())) kW" : "\(Int(snapshot.speedKmH.rounded())) km/h",
                        systemImage: snapshot.isCharging ? "bolt" : "speedometer"
                    )
                    .font(.caption)
                    if snapshot.isTripActive {
                        Label("\(Int(snapshot.distanceKm.rounded())) km", systemImage: "road.lanes")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}
