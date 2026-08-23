import SwiftUI
import Charts
import MapKit

public struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tripTracker: TripTrackingManager
    @State private var showDeleteConfirmation = false
    public let trip: TripModel

    public init(trip: TripModel) {
        self.trip = trip
    }

    private var durationText: String {
        guard let endTime = trip.endTime else { return "In Progress" }
        let interval = endTime.timeIntervalSince(trip.startTime)
        let minutes = Int(interval / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes) m"
    }

    private var topSpeedKmH: Double {
        trip.samples.map(\.speedKmH).max() ?? trip.averageSpeedKmH
    }

    public var body: some View {
        let routeSamples = trip.routeSamples

        ZStack {
            Theme.backgroundDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header Overview Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trip.vehicleName.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.electricCyan)
                                Text(trip.startTime.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundColor(Theme.textPrimary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("DURATION")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.textSecondary)
                                Text(durationText)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.regenGreen)
                            }
                        }

                        if let end = trip.endTime {
                            HStack {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.textSecondary)
                                Text("Time Range: \(trip.startTime.formatted(date: .omitted, time: .standard)) - \(end.formatted(date: .omitted, time: .standard))")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }

                        Divider().background(Color.white.opacity(0.15))

                        // Primary Stats Row
                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("Distance")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.1f km", trip.distanceKm))
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.electricCyan)
                            }

                            Spacer()

                            VStack(alignment: .leading) {
                                Text("Energy Used")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.2f kWh", trip.totalKWhUsed))
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.textPrimary)
                            }

                            Spacer()

                            VStack(alignment: .leading) {
                                Text("Avg Efficiency")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.1f", trip.efficiencyKWhPer100Km))
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
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
                            .font(.system(size: 11, weight: .bold, design: .rounded))
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
                            .font(.system(size: 11, weight: .bold, design: .rounded))
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
                    if !trip.samples.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SPEED & POWER CURVES")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal)

                            VStack(alignment: .leading, spacing: 16) {
                                Text("Speed Profile (km/h)")
                                    .font(.caption).fontWeight(.bold).foregroundColor(Theme.electricCyan)

                                Chart(trip.samples, id: \.timestamp) { sample in
                                    LineMark(
                                        x: .value("Time", sample.timestamp),
                                        y: .value("Speed", sample.speedKmH)
                                    )
                                    .foregroundStyle(Theme.electricCyan)
                                    .interpolationMethod(.catmullRom)

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

                                Chart(trip.samples, id: \.timestamp) { sample in
                                    LineMark(
                                        x: .value("Time", sample.timestamp),
                                        y: .value("Power", sample.powerKW)
                                    )
                                    .foregroundStyle(sample.powerKW >= 0 ? Theme.highPowerAmber : Theme.regenGreen)
                                    .interpolationMethod(.monotone)
                                }
                                .frame(height: 140)
                            }
                            .padding()
                            .glassCard()
                            .padding(.horizontal)
                        }
                    }

                    // Detailed Sample Telemetry Points with Timestamps
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("TELEMETRY LOG (\(trip.samples.count) SAMPLES)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal)

                        if trip.samples.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 36))
                                    .foregroundColor(Theme.textSecondary)
                                Text("No Telemetry Samples Recorded")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .glassCard()
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 0) {
                                // Table Header
                                HStack {
                                    Text("TIMESTAMP").frame(width: 80, alignment: .leading)
                                    Spacer()
                                    Text("SPEED").frame(width: 65, alignment: .trailing)
                                    Spacer()
                                    Text("POWER").frame(width: 65, alignment: .trailing)
                                    Spacer()
                                    Text("SOC").frame(width: 50, alignment: .trailing)
                                    Spacer()
                                    Text("TEMP").frame(width: 55, alignment: .trailing)
                                }
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.05))

                                Divider().background(Color.white.opacity(0.2))

                                ForEach(Array(trip.samples.enumerated()), id: \.offset) { index, sample in
                                    HStack {
                                        Text(sample.timestamp.formatted(date: .omitted, time: .standard))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(Theme.textPrimary)
                                            .frame(width: 80, alignment: .leading)

                                        Spacer()

                                        Text(String(format: "%.0f km/h", sample.speedKmH))
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(Theme.electricCyan)
                                            .frame(width: 65, alignment: .trailing)

                                        Spacer()

                                        Text(String(format: "%.1f kW", sample.powerKW))
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(sample.powerKW < 0 ? Theme.regenGreen : Theme.textPrimary)
                                            .frame(width: 65, alignment: .trailing)

                                        Spacer()

                                        Text(String(format: "%.1f%%", sample.socPct))
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundColor(Theme.textPrimary)
                                            .frame(width: 50, alignment: .trailing)

                                        Spacer()

                                        Text(String(format: "%.0f°C", sample.batteryTempC))
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundColor(Theme.textSecondary)
                                            .frame(width: 55, alignment: .trailing)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(index % 2 == 0 ? Color.clear : Color.white.opacity(0.02))

                                    if index < trip.samples.count - 1 {
                                        Divider().background(Color.white.opacity(0.05))
                                    }
                                }
                            }
                            .glassCard()
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 20)
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
                        .foregroundColor(.red)
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
            #endif
        }
        .confirmationDialog("Delete Trip", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) {
                tripTracker.deleteTrip(trip)
                dismiss()
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
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textSecondary)
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(accentColor)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
