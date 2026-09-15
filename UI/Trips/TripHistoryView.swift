import SwiftUI
import SwiftData

public enum HistoryLogType: String, CaseIterable, Identifiable {
    case trips = "Trips"
    case charging = "Charging"

    public var id: String { rawValue }
}

public struct TripHistoryView: View {
    @EnvironmentObject private var vehicleData: VehicleDataManager
    @ObservedObject public var tripTracker: TripTrackingManager
    @EnvironmentObject private var chargingTracker: ChargingTrackingManager

    @State private var selectedLogType: HistoryLogType = .trips

    @State private var showClearAllConfirmation = false
    @State private var tripToDelete: TripModel?
    @State private var chargeToDelete: ChargingSessionModel?

    @Query(filter: #Predicate<TripModel> { $0.endTime != nil }, sort: \TripModel.startTime, order: .reverse)
    private var persistedTrips: [TripModel]

    @Query(filter: #Predicate<ChargingSessionModel> { $0.endTime != nil }, sort: \ChargingSessionModel.startTime, order: .reverse)
    private var persistedCharges: [ChargingSessionModel]

    private var displayedTrips: [TripModel] {
        vehicleData.isDemoMode ? tripTracker.demoTrips : persistedTrips
    }

    private var displayedCharges: [ChargingSessionModel] {
        vehicleData.isDemoMode ? chargingTracker.demoSessions : persistedCharges
    }

    public init(tripTracker: TripTrackingManager) {
        self.tripTracker = tripTracker
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundDark.ignoresSafeArea()

                VStack(spacing: 12) {
                    // Segmented Control
                    Picker("Log Type", selection: $selectedLogType) {
                        ForEach(HistoryLogType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if selectedLogType == .trips {
                        tripsContent
                    } else {
                        chargingContent
                    }
                }
            }
            .navigationTitle("History")
            .inlineTitleDisplayMode()
            .toolbar {
                let hasItems = selectedLogType == .trips
                    ? (!displayedTrips.isEmpty || tripTracker.currentTrip != nil)
                    : (!displayedCharges.isEmpty || chargingTracker.currentSession != nil)
                if hasItems {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showClearAllConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(Theme.criticalRed)
                        }
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        Button(role: .destructive) {
                            showClearAllConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    #endif
                }
            }
            .confirmationDialog(
                selectedLogType == .trips ? "Clear All Trips" : "Clear All Charging Sessions",
                isPresented: $showClearAllConfirmation,
                titleVisibility: .visible
            ) {
                Button(selectedLogType == .trips ? "Clear All Trips" : "Clear All Sessions", role: .destructive) {
                    if selectedLogType == .trips {
                        tripTracker.clearAllTrips()
                    } else {
                        chargingTracker.clearAllSessions()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(selectedLogType == .trips
                    ? "Are you sure you want to clear all trip history? This action cannot be undone."
                    : "Are you sure you want to clear all charging history? This action cannot be undone.")
            }
            .confirmationDialog(
                "Delete Trip",
                isPresented: Binding(
                    get: { tripToDelete != nil },
                    set: { if !$0 { tripToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Trip", role: .destructive) {
                    if let trip = tripToDelete {
                        performDeleteTrip(trip)
                    }
                    tripToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    tripToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this trip record?")
            }
            .confirmationDialog(
                "Delete Charging Session",
                isPresented: Binding(
                    get: { chargeToDelete != nil },
                    set: { if !$0 { chargeToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Session", role: .destructive) {
                    if let session = chargeToDelete {
                        performDeleteCharge(session)
                    }
                    chargeToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    chargeToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this charging session record?")
            }
        }
        .id(vehicleData.isDemoMode)
    }

    // MARK: - Trips View Content

    @ViewBuilder
    private var tripsContent: some View {
        VStack {
            if let active = tripTracker.currentTrip {
                NavigationLink(destination: TripDetailView(trip: active)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("CURRENT ACTIVE TRIP")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.regenGreen)
                            Spacer()
                            ProgressView().tint(Theme.regenGreen)
                        }

                        HStack(spacing: 20) {
                            VStack(alignment: .leading) {
                                Text("Distance")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.1f km", active.distanceKm))
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(Theme.textPrimary)
                            }

                            VStack(alignment: .leading) {
                                Text("Energy Used")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.2f kWh", active.totalKWhUsed))
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(Theme.textPrimary)
                            }

                            VStack(alignment: .leading) {
                                Text("SOC Delta")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "-%.1f%%", max(0, active.startSocPct - active.endSocPct)))
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(Theme.electricCyan)
                            }
                        }
                    }
                    .padding()
                    .glassCard()
                    .padding(.horizontal)
                }
            }

            if displayedTrips.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "road.lanes")
                        .font(.system(size: 50))
                        .foregroundColor(Theme.textSecondary)
                    Text("No Past Trips Recorded")
                        .font(.headline)
                    Text("Start a trip on the Dashboard to record GPS route, speed curve, and energy consumption.")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                List {
                    ForEach(Array(displayedTrips.enumerated()), id: \.element.id) { index, trip in
                        NavigationLink(destination: TripDetailView(trip: trip)) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(trip.startTime.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 14, weight: .bold))
                                    Spacer()
                                    Text(String(format: "%.1f km", trip.distanceKm))
                                        .font(.headline)
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
                        .swipeActions(edge: .leading) {
                            if index + 1 < displayedTrips.count,
                               tripTracker.canMerge(trip, into: displayedTrips[index + 1]) {
                                let previousTrip = displayedTrips[index + 1]
                                Button {
                                    guard !trip.isDeleted, !previousTrip.isDeleted else { return }
                                    tripTracker.merge(trip, into: previousTrip)
                                } label: {
                                    Label("Merge with previous", systemImage: "arrow.triangle.merge")
                                }
                                .tint(Theme.electricCyan)
                            }
                        }
                    }
                    .onDelete(perform: deleteTrips)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Charging View Content

    @ViewBuilder
    private var chargingContent: some View {
        VStack {
            if let active = chargingTracker.currentSession {
                NavigationLink(destination: ChargingSessionDetailView(session: active)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("CURRENT CHARGING SESSION")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.regenGreen)
                            Spacer()
                            ProgressView().tint(Theme.regenGreen)
                        }

                        HStack(spacing: 20) {
                            VStack(alignment: .leading) {
                                Text("Energy Added")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.2f kWh", active.totalKWhDelivered))
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(Theme.regenGreen)
                            }

                            VStack(alignment: .leading) {
                                Text("Peak Power")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.1f kW", active.peakPowerKW))
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(Theme.highPowerAmber)
                            }

                            VStack(alignment: .leading) {
                                Text("SOC Gained")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "+%.1f%%", max(0, active.endSocPct - active.startSocPct)))
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(Theme.electricCyan)
                            }
                        }
                    }
                    .padding()
                    .glassCard()
                    .padding(.horizontal)
                }
            }

            if displayedCharges.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bolt.batteryblock")
                        .font(.system(size: 50))
                        .foregroundColor(Theme.textSecondary)
                    Text("No Past Charging Sessions")
                        .font(.headline)
                    Text("Plug in to charge or simulate DC fast charging to record sessions with location and power curves.")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                List {
                    ForEach(displayedCharges) { session in
                        NavigationLink(destination: ChargingSessionDetailView(session: session)) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 14, weight: .bold))
                                    Spacer()
                                    Text(String(format: "+%.2f kWh", session.totalKWhDelivered))
                                        .font(.headline)
                                        .foregroundColor(Theme.regenGreen)
                                }
                                HStack {
                                    Label(session.locationName, systemImage: "mappin.and.ellipse")
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "Peak: %.1f kW", session.peakPowerKW))
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                            }
                        }
                        .listRowBackground(Theme.cardBackground)
                    }
                    .onDelete(perform: deleteCharges)
                }
                .listStyle(.plain)
            }
        }
    }

    private func deleteTrips(at offsets: IndexSet) {
        if let index = offsets.first, index < displayedTrips.count {
            tripToDelete = displayedTrips[index]
        }
    }

    private func deleteCharges(at offsets: IndexSet) {
        if let index = offsets.first, index < displayedCharges.count {
            chargeToDelete = displayedCharges[index]
        }
    }

    private func performDeleteTrip(_ trip: TripModel) {
        tripTracker.deleteTrip(trip)
    }

    private func performDeleteCharge(_ session: ChargingSessionModel) {
        chargingTracker.deleteSession(session)
    }
}

#Preview("Trip & Charging History View") {
    TripHistoryView(
        tripTracker: TripTrackingManager()
    )
    .environmentObject(VehicleDataManager())
    .environmentObject(ChargingTrackingManager())
}
