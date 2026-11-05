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
                vehicleName: "Mercedes-Benz EQA 250", socPct: 68, powerKW: 42, speedKmH: 0, rangeKm: 312, isCharging: true, isConnected: true,
                lastTripConsumptionKWhPer100Km: 18.6)
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
        .description("State of charge, estimated range, charging power, and the last trip's consumption.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
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
            case .systemLarge:
                largeContent(for: snapshot)
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

    /// The large size has room for the numbers a parked glance wants: battery, range, and
    /// how the last completed trip consumed.
    private func largeContent(for snapshot: SharedTelemetrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BATTERY")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if snapshot.isDemoMode { DemoBadge() }
                Spacer()
                if snapshot.isCharging {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(snapshot.socPct.rounded()))")
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                Text("%")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("RANGE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(rangeText(for: snapshot))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text("LAST TRIP")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let consumption = snapshot.lastTripConsumptionKWhPer100Km {
                    Text(
                        "Ø \(String(format: "%.1f", units.efficiency(kilowattHoursPer100Kilometers: consumption))) \(units.efficiencySymbol)"
                    )
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                }
                if let details = lastTripDetails(for: snapshot) {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if snapshot.lastTripConsumptionKWhPer100Km == nil {
                    Text("No completed trip yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Divider()

            HStack(spacing: 10) {
                Label(statusText(for: snapshot), systemImage: statusIcon(for: snapshot))
                Spacer(minLength: 0)
                if snapshot.isTripActive {
                    Label(
                        "\(Int(units.distance(kilometers: snapshot.distanceKm).rounded())) \(units.distanceSymbol)",
                        systemImage: "road.lanes")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Distance and duration under the average, whichever parts the recording has.
    private func lastTripDetails(for snapshot: SharedTelemetrySnapshot) -> String? {
        var parts: [String] = []
        if let distance = snapshot.lastTripDistanceKm, distance > 0 {
            parts.append("\(String(format: "%.1f", units.distance(kilometers: distance))) \(units.distanceSymbol)")
        }
        if let duration = snapshot.lastTripDurationSeconds, duration > 0 {
            parts.append(durationText(duration))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    private func rangeText(for snapshot: SharedTelemetrySnapshot) -> String {
        guard let range = snapshot.rangeKm, range > 0 else { return "--" }
        return "≈ \(Int(units.distance(kilometers: range).rounded())) \(units.distanceSymbol)"
    }

    private func statusText(for snapshot: SharedTelemetrySnapshot) -> String {
        if snapshot.isCharging {
            return "\(Int(units.power(kilowatts: snapshot.powerKW).rounded())) \(units.powerSymbol)"
        }
        return snapshot.isConnected ? "Connected" : "No connection"
    }

    private func statusIcon(for snapshot: SharedTelemetrySnapshot) -> String {
        snapshot.isCharging ? "bolt.fill" : (snapshot.isConnected ? "checkmark.circle" : "bolt.slash")
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
