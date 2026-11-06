import SwiftUI
import Charts
import MapKit

public struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TripTrackingManager.self) private var tripTracker
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    public let trip: TripModel

    public init(trip: TripModel) {
        self.trip = trip
    }

    private var durationText: String {
        guard let endTime = trip.endTime else { return "In Progress" }
        let interval = endTime.timeIntervalSince(trip.startTime)
        guard interval >= 0, let minutes = Int(exactly: (interval / 60).rounded(.towardZero)) else {
            return "Unavailable"
        }
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes) m"
    }

    /// Display-only sampling keeps long trips bounded without deleting recorded telemetry.
    /// Uniform spacing by default, which suits route geometry. Pass `extremaOf` to keep each
    /// bucket's lowest and highest sample instead, so brief speed or power peaks survive the
    /// downsample rather than falling between two kept points.
    static func displaySamples(
        _ samples: [TelemetryPointModel],
        limit: Int,
        extremaOf metric: ((TelemetryPointModel) -> Double)? = nil
    ) -> [TelemetryPointModel] {
        guard limit > 1 else { return Array(samples.prefix(max(0, limit))) }
        guard samples.count > limit else { return samples }
        guard limit > 2, let metric else {
            return (0..<limit).map { samples[$0 * (samples.count - 1) / (limit - 1)] }
        }

        // Two slots hold the endpoints; the rest are spent in pairs, one bucket per pair.
        let budget = limit - 2
        let bucketCount = budget / 2
        var selected: [TelemetryPointModel] = [samples[0]]
        var cursor = 1
        if budget % 2 == 1 {
            selected.append(samples[cursor])
            cursor += 1
        }
        // Every bucket holds at least two samples, so it can yield a distinct min and max.
        let interiorCount = samples.count - 1 - cursor
        for bucket in 0..<bucketCount {
            let start = cursor + bucket * interiorCount / bucketCount
            let end = cursor + (bucket + 1) * interiorCount / bucketCount
            var low = start
            var high = start
            for index in start..<end {
                let value = metric(samples[index])
                if value < metric(samples[low]) { low = index }
                if value > metric(samples[high]) { high = index }
            }
            if low == high {
                high = low == start ? start + 1 : start
            }
            selected.append(contentsOf: [low, high].sorted().map { samples[$0] })
        }
        selected.append(samples[samples.count - 1])
        return selected
    }

    public var body: some View {
        Group {
            if isDeleting || trip.isDeleted {
                Color.clear
            } else {
                detailContent
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            ShareLink(
                item: TripGPXExport(trip: trip),
                preview: SharePreview("Trip GPX", image: Image(systemName: "map"))
            ) {
                Label("Export GPX", systemImage: "map")
            }
            ShareLink(
                item: TripCSVExport(trip: trip),
                preview: SharePreview("Trip CSV", image: Image(systemName: "tablecells"))
            ) {
                Label("Export CSV", systemImage: "tablecells")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Export trip")
    }

    private var detailContent: some View {
        let samples = trip.samplePoints.filter { $0.timestamp.timeIntervalSince1970.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
        let chartSource = samples.filter { $0.speedKmH.isFinite && $0.powerKW.isFinite }
        // Each curve keeps its own peaks; the route keeps uniform spacing for an even polyline.
        let speedSamples = Self.displaySamples(chartSource, limit: 500) { $0.speedKmH }
        let powerSamples = Self.displaySamples(chartSource, limit: 500) { $0.powerKW }
        let routeSamples = Self.displaySamples(trip.routeSamples, limit: 2_000)
        let topSpeedKmH = samples.lazy.map(\.speedKmH).filter(\.isFinite).max() ?? trip.averageSpeedKmH

        return ZStack {
            Theme.backgroundDark.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 20) {
                    // Header Overview Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trip.vehicleName.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.electricCyan)
                                Text(trip.startTime.formatted(date: .abbreviated, time: .shortened))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("DURATION")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                Text(durationText)
                                    .font(.headline)
                                    .foregroundStyle(Theme.regenGreen)
                            }
                        }

                        if let end = trip.endTime {
                            HStack {
                                Image(systemName: "clock.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(
                                    "Time Range: \(trip.startTime.formatted(date: .omitted, time: .standard)) - \(end.formatted(date: .omitted, time: .standard))"
                                )
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        Divider().background(Theme.divider)

                        // Primary Stats Row
                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("Distance")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                Text(UnitPreferences.shared.distance(kilometers: trip.distanceKm))
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(Theme.electricCyan)
                            }

                            Spacer()

                            VStack(alignment: .leading) {
                                Text("Energy Used")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                Text(UnitPreferences.shared.energy(kilowattHours: trip.totalKWhUsed))
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                            }

                            Spacer()

                            VStack(alignment: .leading) {
                                Text("Avg Efficiency")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text(
                                        String(
                                            format: "%.1f",
                                            UnitPreferences.shared.efficiencyValue(fromKilowattHoursPer100Kilometers: trip.efficiencyKWhPer100Km))
                                    )
                                    .font(.title2.weight(.semibold))
                                    Text(UnitPreferences.shared.efficiencyUnit)
                                        .font(.caption)
                                }
                                .foregroundStyle(Theme.regenGreen)
                            }
                        }
                    }
                    .padding()
                    .glassCard()
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("DRIVEN ROUTE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal)

                        if routeSamples.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "map")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Theme.textSecondary)
                                Text("No GPS Route Recorded")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Enable GPS Route Recording in Settings before starting a trip.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .glassCard()
                            .padding(.horizontal)
                        } else {
                            Map(initialPosition: .automatic) {
                                if routeSamples.count > 1 {
                                    MapPolyline(
                                        coordinates: routeSamples.map {
                                            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                                        }
                                    )
                                    .stroke(Theme.electricCyan, lineWidth: 5)
                                }

                                if let start = routeSamples.first {
                                    Marker(
                                        "Trip start", systemImage: "flag.fill",
                                        coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude))
                                }

                                if let end = routeSamples.last, routeSamples.count > 1 {
                                    Marker(
                                        trip.endTime == nil ? "Latest location" : "Trip end", systemImage: "mappin.circle.fill",
                                        coordinate: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude)
                                    )
                                    .tint(Theme.regenGreen)
                                }
                            }
                            .mapStyle(.standard(elevation: .realistic))
                            .frame(height: 240)
                            .clipShape(.rect(cornerRadius: 16))
                            .accessibilityLabel("Trip route with \(routeSamples.count) GPS points")
                            .padding(.horizontal)
                        }
                    }

                    // Secondary Performance Grid
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PERFORMANCE METRICS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            TripStatTile(
                                title: "SOC Delta",
                                value: String(format: "%.0f%% → %.0f%%", trip.startSocPct, trip.endSocPct),
                                subtitle: String(format: "-%.1f%% used", max(0, trip.startSocPct - trip.endSocPct)),
                                accentColor: Theme.electricCyan
                            )

                            TripStatTile(
                                title: "Peak Regen Braking",
                                value: UnitPreferences.shared.power(kilowatts: abs(trip.maxRegenKW)),
                                subtitle: "Max kinetic recovery",
                                accentColor: Theme.regenGreen
                            )

                            TripStatTile(
                                title: "Top Speed",
                                value: UnitPreferences.shared.speed(kilometersPerHour: topSpeedKmH, decimals: 0),
                                subtitle: "Peak speed recorded",
                                accentColor: Theme.highPowerAmber
                            )

                            TripStatTile(
                                title: "Avg Speed",
                                value: UnitPreferences.shared.speed(kilometersPerHour: trip.computedAverageSpeedKmH, decimals: 0),
                                subtitle: "Average travel speed",
                                accentColor: Theme.electricCyan
                            )

                            TripStatTile(
                                title: "Avg Power Draw",
                                value: UnitPreferences.shared.power(kilowatts: trip.averagePowerKW),
                                subtitle: "Mean electrical power",
                                accentColor: Theme.electricCyan
                            )

                            TripStatTile(
                                title: "Peak Power Draw",
                                value: UnitPreferences.shared.power(kilowatts: trip.maxPowerKW),
                                subtitle: "Max motor output",
                                accentColor: Theme.highPowerAmber
                            )
                        }
                        .padding(.horizontal)
                    }

                    // Interactive Telemetry Charts (Speed & Power over Time)
                    if !speedSamples.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SPEED & POWER CURVES")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal)

                            VStack(alignment: .leading, spacing: 16) {
                                Text("Speed Profile (\(UnitPreferences.shared.distanceUnit.perHourSymbol))")
                                    .font(.caption).fontWeight(.bold).foregroundStyle(Theme.electricCyan)

                                Chart(speedSamples, id: \.persistentModelID) { sample in
                                    LineMark(
                                        x: .value("Time", sample.timestamp),
                                        y: .value("Speed", UnitPreferences.shared.speedValue(fromKilometersPerHour: sample.speedKmH))
                                    )
                                    .foregroundStyle(Theme.electricCyan)
                                    .interpolationMethod(.linear)

                                    AreaMark(
                                        x: .value("Time", sample.timestamp),
                                        y: .value("Speed", UnitPreferences.shared.speedValue(fromKilometersPerHour: sample.speedKmH))
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Theme.electricCyan.opacity(0.3), Theme.electricCyan.opacity(0.0)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                }
                                .frame(height: 140)

                                Divider().background(Theme.divider)

                                Text("Power Draw & Regen (\(UnitPreferences.shared.powerUnit.symbol))")
                                    .font(.caption).fontWeight(.bold).foregroundStyle(Theme.regenGreen)

                                Chart(powerSamples, id: \.persistentModelID) { sample in
                                    LineMark(
                                        x: .value("Time", sample.timestamp),
                                        y: .value("Power", UnitPreferences.shared.powerValue(fromKilowatts: sample.powerKW))
                                    )
                                    .foregroundStyle(sample.powerKW >= 0 ? Theme.highPowerAmber : Theme.regenGreen)
                                    .interpolationMethod(.linear)
                                }
                                .frame(height: 140)
                            }
                            .padding()
                            .glassCard()
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Trip Details")
        .inlineTitleDisplayMode()
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                exportMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.criticalRed)
                }
                .accessibilityLabel("Delete trip")
            }
            #else
            ToolbarItem(placement: .automatic) {
                exportMenu
            }
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.criticalRed)
                }
                .accessibilityLabel("Delete trip")
            }
            #endif
        }
        .confirmationDialog("Delete Trip", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) {
                isDeleting = true
                dismiss()
                tripTracker.deleteTrip(trip)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this trip record?")
        }
    }
}

private struct TripStatTile: View {
    let title: String
    let value: String
    let subtitle: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(accentColor)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
