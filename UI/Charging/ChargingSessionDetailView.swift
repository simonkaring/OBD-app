import SwiftUI
import SwiftData
import MapKit

public struct ChargingSessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chargingTracker: ChargingTrackingManager
    @State private var showDeleteConfirmation = false
    public let session: ChargingSessionModel

    public init(session: ChargingSessionModel) {
        self.session = session
    }

    private var durationText: String {
        guard let endTime = session.endTime else { return "In Progress" }
        let interval = endTime.timeIntervalSince(session.startTime)
        let minutes = Int(interval / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(max(1, minutes))m"
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = session.latitude, let lon = session.longitude,
              (-90...90).contains(lat), (-180...180).contains(lon),
              !(lat == 0 && lon == 0) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    public var body: some View {
        ZStack {
            Theme.backgroundDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header Overview Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.locationName.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Theme.regenGreen)
                                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
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
                                    .foregroundColor(Theme.electricCyan)
                            }
                        }

                        if let end = session.endTime {
                            HStack {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.textSecondary)
                                Text("Time Range: \(session.startTime.formatted(date: .omitted, time: .standard)) - \(end.formatted(date: .omitted, time: .standard))")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }

                        Divider().background(Theme.divider)

                        // Primary Stats Row
                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("Energy Added")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.2f kWh", session.totalKWhDelivered))
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(Theme.regenGreen)
                            }

                            Spacer()

                            VStack(alignment: .leading) {
                                Text("Peak Power")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.1f kW", session.peakPowerKW))
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(Theme.highPowerAmber)
                            }

                            Spacer()

                            VStack(alignment: .leading) {
                                Text("Avg Power")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.1f kW", session.averagePowerKW))
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(Theme.electricCyan)
                            }
                        }
                    }
                    .padding()
                    .glassCard()
                    .padding(.horizontal)

                    // Location Map
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CHARGING LOCATION")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal)

                        if let coord = coordinate {
                            Map(initialPosition: .region(MKCoordinateRegion(
                                center: coord,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            ))) {
                                Marker(session.locationName, systemImage: "bolt.fill", coordinate: coord)
                                    .tint(Theme.regenGreen)
                            }
                            .mapStyle(.standard(elevation: .realistic))
                            .frame(height: 200)
                            .clipShape(.rect(cornerRadius: 16))
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "location.slash")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Theme.textSecondary)
                                Text("No GPS Location Recorded")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Location coordinates were unavailable during this charging session.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .glassCard()
                            .padding(.horizontal)
                        }
                    }

                    // Performance Grid
                    VStack(alignment: .leading, spacing: 12) {
                        Text("BATTERY & CHARGE STATS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            StatTile(
                                title: "SOC Delta",
                                value: String(format: "%.0f%% → %.0f%%", session.startSocPct, session.endSocPct),
                                subtitle: String(format: "+%.1f%% gained", max(0, session.endSocPct - session.startSocPct)),
                                accentColor: Theme.regenGreen
                            )

                            StatTile(
                                title: "Start SOC",
                                value: String(format: "%.1f%%", session.startSocPct),
                                subtitle: "Initial charge level",
                                accentColor: Theme.electricCyan
                            )

                            StatTile(
                                title: "Peak Power",
                                value: String(format: "%.1f kW", session.peakPowerKW),
                                subtitle: "Maximum charging rate",
                                accentColor: Theme.highPowerAmber
                            )

                            StatTile(
                                title: "Energy Delivered",
                                value: String(format: "%.2f kWh", session.totalKWhDelivered),
                                subtitle: "Total net energy",
                                accentColor: Theme.regenGreen
                            )
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Charging Session")
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
        .confirmationDialog("Delete Charging Session", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Session", role: .destructive) {
                chargingTracker.deleteSession(session)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this charging session record?")
        }
    }
}

private struct StatTile: View {
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
