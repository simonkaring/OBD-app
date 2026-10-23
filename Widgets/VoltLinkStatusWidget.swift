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
        completion(SharedSnapshotEntry(date: Date(), snapshot: SharedTelemetryStore.loadFresh()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SharedSnapshotEntry>) -> Void) {
        // A snapshot the app stopped refreshing no longer describes the car; the view
        // falls back to its placeholder instead of showing last night's charge rate.
        let snapshot = SharedTelemetryStore.loadFresh()
        let entry = SharedSnapshotEntry(date: Date(), snapshot: snapshot)
        // The app reloads timelines whenever telemetry meaningfully changes, so the policy
        // below only has to cover the app going away. A fresh snapshot schedules exactly
        // one re-render for the moment it expires (which then shows the placeholder); the
        // placeholder itself needs no early refresh.
        let next: Date
        if let snapshot {
            next = max(
                snapshot.updatedAt.addingTimeInterval(SharedTelemetrySnapshot.maximumAge + 1),
                Date().addingTimeInterval(60))
        } else {
            next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        }
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
    private var units: SharedDisplayUnits { snapshot?.units ?? SharedDisplayUnits() }
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
                    Text("\(Int(soc.rounded()))% · \(Int(units.distance(kilometers: snapshot.rangeKm ?? 0).rounded())) \(units.distanceSymbol)")
                        .font(.headline)
                    Text(
                        (snapshot.isDemoMode ? "Demo · " : "")
                            + (snapshot.isCharging
                                ? "Charging \(Int(units.power(kilowatts: snapshot.powerKW).rounded())) \(units.powerSymbol)"
                                : (snapshot.isConnected ? "Connected" : "Disconnected"))
                    )
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
                if snapshot.isDemoMode { DemoBadge() }
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
                Text("≈ \(Int(units.distance(kilometers: range).rounded())) \(units.distanceSymbol)")
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
                        snapshot.isCharging
                            ? "\(Int(units.power(kilowatts: snapshot.powerKW).rounded())) \(units.powerSymbol)"
                            : "\(Int(units.speed(kilometersPerHour: snapshot.speedKmH).rounded())) \(units.speedSymbol)",
                        systemImage: snapshot.isCharging ? "bolt" : "speedometer"
                    )
                    .font(.caption)
                    if snapshot.isTripActive {
                        Label(
                            "\(Int(units.distance(kilometers: snapshot.distanceKm).rounded())) \(units.distanceSymbol)",
                            systemImage: "road.lanes"
                        )
                        .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Marks simulated values so a Home Screen or Lock Screen reading is never mistaken
/// for the car's real state.
struct DemoBadge: View {
    var body: some View {
        Text("DEMO")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.orange.opacity(0.2), in: Capsule())
    }
}
