import SwiftUI
import Charts
import MapKit

public struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tripTracker: TripTrackingManager
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

    // Display-only sampling keeps long trips bounded without deleting recorded telemetry.
    // ponytail: uniform sampling may miss brief peaks; use an extrema-preserving algorithm if needed.
    static func displaySamples(_ samples: [TelemetryPointModel], limit: Int) -> [TelemetryPointModel] {
        guard limit > 1 else { return Array(samples.prefix(max(0, limit))) }
        guard samples.count > limit else { return samples }
        return (0..<limit).map { samples[$0 * (samples.count - 1) / (limit - 1)] }
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

    private var detailContent: some View {
        let samples = trip.samples.filter { $0.timestamp.timeIntervalSince1970.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
        let chartSamples = Self.displaySamples(samples.filter { $0.speedKmH.isFinite && $0.powerKW.isFinite }, limit: 500)
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
                                    .foregroundColor(Theme.electricCyan)
                                Text(trip.startTime.formatted(date: .abbreviated, time: .shortened))
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(Theme.textPrimary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("DURATION")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Theme.textSecondary)
                                Text(durationText)
                                    .font(.headline)
                                    .foregroundColor(Theme.regenGreen)
                            }
                        }

                        if let end = trip.endTime {
                            HStack {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.textSecondary)
                                Text("Time Range: \(trip.startTime.formatted(date: .omitted, time: .standard)) - \(end.formatted(date: .omitted, time: .standard))")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }

                        Divider().background(Theme.divider)

                        // Primary Stats Row
                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("Distance")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.1f km", trip.distanceKm))
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(Theme.electricCyan)
                            }

                            Spacer()

                            VStack(alignment: .leading) {
                                Text("Energy Used")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.2f kWh", trip.totalKWhUsed))
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(Theme.textPrimary)
                            }

                            Spacer()

                            VStack(alignment: .leading) {
                                Text("Avg Efficiency")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.1f", trip.efficiencyKWhPer100Km))
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(Theme.regenGreen) +
                                Text(" kWh/100km").font(.caption).foregroundColor(Theme.textSecondary)
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
                                    MapPolyline(coordinates: routeSamples.map {
                                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                                    })
                                    .stroke(Theme.electricCyan, lineWidth: 5)
                                }

                                if let start = routeSamples.first {
                                    Marker("Trip start", systemImage: "flag.fill", coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude))
                                }

                                if let end = routeSamples.last, routeSamples.count > 1 {
                                    Marker(trip.endTime == nil ? "Latest location" : "Trip end", systemImage: "mappin.circle.fill", coordinate: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude))
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
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            TripStatTile(
                                title: "SOC Delta",
                                value: String(format: "%.0f%% → %.0f%%", trip.startSocPct, trip.endSocPct),
                                subtitle: String(format: "-%.1f%% used", max(0, trip.startSocPct - trip.endSocPct)),
                                accentColor: Theme.electricCyan
                            )

                            TripStatTile(
                                title: "Top Speed",
                                value: String(format: "%.0f km/h", topSpeedKmH),
                                subtitle: "Peak speed recorded",
                                accentColor: Theme.highPowerAmber
                            )

                            TripStatTile(
                                title: "Avg Speed",
                                value: String(format: "%.0f km/h", trip.computedAverageSpeedKmH),
                                subtitle: "Average travel speed",
                                accentColor: Theme.electricCyan
                            )

                            TripStatTile(
                                title: "Avg Power Draw",
                                value: String(format: "%.1f kW", trip.averagePowerKW),
                                subtitle: "Mean electrical power",
                                accentColor: Theme.electricCyan
                            )

                            TripStatTile(
                                title: "Peak Power Draw",
                                value: String(format: "%.1f kW", trip.maxPowerKW),
                                subtitle: "Max motor output",
                                accentColor: Theme.highPowerAmber
                            )

                            TripStatTile(
                                title: "Peak Regen Braking",
                                value: String(format: "%.1f kW", abs(trip.maxRegenKW)),
                                subtitle: "Max kinetic recovery",
                                accentColor: Theme.regenGreen
                            )
                        }
                        .padding(.horizontal)
                    }

                    // Interactive Telemetry Charts (Speed & Power over Time)
                    if !chartSamples.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SPEED & POWER CURVES")
                            .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal)

                            VStack(alignment: .leading, spacing: 16) {
                                Text("Speed Profile (km/h)")
                                    .font(.caption).fontWeight(.bold).foregroundColor(Theme.electricCyan)

                                Chart(chartSamples, id: \.persistentModelID) { sample in
                                    LineMark(
                                        x: .value("Time", sample.timestamp),
                                        y: .value("Speed", sample.speedKmH)
                                    )
                                    .foregroundStyle(Theme.electricCyan)
                                    .interpolationMethod(.linear)

                                    AreaMark(
                                        x: .value("Time", sample.timestamp),
                                        y: .value("Speed", sample.speedKmH)
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

                                Divider().background(Color.white.opacity(0.1))

                                Text("Power Draw & Regen (kW)")
                                    .font(.caption).fontWeight(.bold).foregroundColor(Theme.regenGreen)

                                Chart(chartSamples, id: \.persistentModelID) { sample in
                                    LineMark(
                                        x: .value("Time", sample.timestamp),
                                        y: .value("Power", sample.powerKW)
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
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(Theme.criticalRed)
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(Theme.criticalRed)
                }
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
                .foregroundColor(Theme.textSecondary)
            Text(value)
                .font(.headline)
                .foregroundColor(accentColor)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
