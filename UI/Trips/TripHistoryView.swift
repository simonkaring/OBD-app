import SwiftUI

public struct TripHistoryView: View {
    @EnvironmentObject private var vehicleData: VehicleDataManager
    @ObservedObject public var tripTracker: TripTrackingManager
    @State private var sampleTrips: [TripModel] = []

    public init(tripTracker: TripTrackingManager) {
        self.tripTracker = tripTracker
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundDark.ignoresSafeArea()

                VStack {
                    if let active = tripTracker.currentTrip {
                        NavigationLink(destination: TripDetailView(trip: active)) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("CURRENT ACTIVE TRIP")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.regenGreen)
                                    Spacer()
                                    ProgressView().tint(Theme.regenGreen)
                                }

                                HStack(spacing: 20) {
                                    VStack(alignment: .leading) {
                                        Text("Distance")
                                            .font(.caption).foregroundColor(Theme.textSecondary)
                                        Text(String(format: "%.1f km", active.distanceKm))
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundColor(Theme.textPrimary)
                                    }

                                    VStack(alignment: .leading) {
                                        Text("Energy Used")
                                            .font(.caption).foregroundColor(Theme.textSecondary)
                                        Text(String(format: "%.2f kWh", active.totalKWhUsed))
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundColor(Theme.textPrimary)
                                    }

                                    VStack(alignment: .leading) {
                                        Text("SOC Delta")
                                            .font(.caption).foregroundColor(Theme.textSecondary)
                                        Text(String(format: "-%.1f%%", max(0, active.startSocPct - active.endSocPct)))
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundColor(Theme.electricCyan)
                                    }
                                }
                            }
                            .padding()
                            .glassCard()
                            .padding(.horizontal)
                        }
                    }

                    if sampleTrips.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "road.lanes")
                                .font(.system(size: 50))
                                .foregroundColor(Theme.textSecondary)
                            Text("No Past Trips Recorded")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("Start a trip on the Dashboard to record GPS route, speed curve, and energy consumption.")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            Spacer()
                        }
                    } else {
                        List(sampleTrips, id: \.id) { trip in
                            NavigationLink(destination: TripDetailView(trip: trip)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(trip.startTime.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 14, weight: .bold))
                                        Spacer()
                                        Text(String(format: "%.1f km", trip.distanceKm))
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundColor(Theme.electricCyan)
                                    }
                                    HStack {
                                        Text(String(format: "Efficiency: %.1f kWh/100km", trip.efficiencyKWhPer100Km))
                                            .font(.caption)
                                            .foregroundColor(Theme.textSecondary)
                                        Spacer()
                                        Text(String(format: "%.1f kWh", trip.totalKWhUsed))
                                            .font(.caption)
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                            }
                            .listRowBackground(Theme.cardBackground)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Trip Log")
            .inlineTitleDisplayMode()
            .toolbar {
                if !sampleTrips.isEmpty || tripTracker.currentTrip != nil {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            sampleTrips.removeAll()
                            tripTracker.clearAllTrips()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        Button(role: .destructive) {
                            sampleTrips.removeAll()
                            tripTracker.clearAllTrips()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    #endif
                }
            }
            .onAppear {
                updateSampleHistory()
            }
            .onChange(of: vehicleData.isDemoMode) { _, _ in
                updateSampleHistory()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ClearSampleTrips"))) { _ in
                sampleTrips.removeAll()
            }
        }
    }

    private func updateSampleHistory() {
        if vehicleData.isDemoMode {
            if sampleTrips.isEmpty {
                let t1 = TripModel(startTime: Date().addingTimeInterval(-86400), distanceKm: 24.8, startSocPct: 85.0, vehicleName: "Mercedes EQA 250")
                t1.endSocPct = 78.0
                t1.totalKWhUsed = 4.8
                
                let t2 = TripModel(startTime: Date().addingTimeInterval(-172800), distanceKm: 68.2, startSocPct: 92.0, vehicleName: "Mercedes EQA 250")
                t2.endSocPct = 72.0
                t2.totalKWhUsed = 13.2

                sampleTrips = [t1, t2]
            }
        } else {
            sampleTrips.removeAll()
        }
    }
}
