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
    @State private var sampleTrips: [TripModel] = []
    @State private var sampleCharges: [ChargingSessionModel] = []

    @Query(filter: #Predicate<TripModel> { $0.endTime != nil }, sort: \TripModel.startTime, order: .reverse)
    private var persistedTrips: [TripModel]

    @Query(filter: #Predicate<ChargingSessionModel> { $0.endTime != nil }, sort: \ChargingSessionModel.startTime, order: .reverse)
    private var persistedCharges: [ChargingSessionModel]

    private var displayedTrips: [TripModel] {
        vehicleData.isDemoMode ? sampleTrips : persistedTrips
    }

    private var displayedCharges: [ChargingSessionModel] {
        vehicleData.isDemoMode ? sampleCharges : persistedCharges
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
                            if selectedLogType == .trips {
                                sampleTrips.removeAll()
                                tripTracker.clearAllTrips()
                            } else {
                                sampleCharges.removeAll()
                                chargingTracker.clearAllSessions()
                            }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        Button(role: .destructive) {
                            if selectedLogType == .trips {
                                sampleTrips.removeAll()
                                tripTracker.clearAllTrips()
                            } else {
                                sampleCharges.removeAll()
                                chargingTracker.clearAllSessions()
                            }
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
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ClearSampleChargingSessions"))) { _ in
                sampleCharges.removeAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DeleteTripNotification"))) { note in
                if let tripID = note.object as? UUID {
                    sampleTrips.removeAll { $0.id == tripID }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DeleteChargingSessionNotification"))) { note in
                if let sessionID = note.object as? UUID {
                    sampleCharges.removeAll { $0.id == sessionID }
                }
            }
        }
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

            if displayedTrips.isEmpty {
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
                List {
                    ForEach(Array(displayedTrips.enumerated()), id: \.element.id) { index, trip in
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
                        .swipeActions(edge: .leading) {
                            if index + 1 < displayedTrips.count,
                               tripTracker.canMerge(trip, into: displayedTrips[index + 1]) {
                                Button {
                                    tripTracker.merge(trip, into: displayedTrips[index + 1])
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
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.regenGreen)
                            Spacer()
                            ProgressView().tint(Theme.regenGreen)
                        }

                        HStack(spacing: 20) {
                            VStack(alignment: .leading) {
                                Text("Energy Added")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.2f kWh", active.totalKWhDelivered))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.regenGreen)
                            }

                            VStack(alignment: .leading) {
                                Text("Peak Power")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "%.1f kW", active.peakPowerKW))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.highPowerAmber)
                            }

                            VStack(alignment: .leading) {
                                Text("SOC Gained")
                                    .font(.caption).foregroundColor(Theme.textSecondary)
                                Text(String(format: "+%.1f%%", max(0, active.endSocPct - active.startSocPct)))
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

            if displayedCharges.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bolt.batteryblock")
                        .font(.system(size: 50))
                        .foregroundColor(Theme.textSecondary)
                    Text("No Past Charging Sessions")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
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
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
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
        for index in offsets {
            let trip = displayedTrips[index]
            tripTracker.deleteTrip(trip)
        }
        if vehicleData.isDemoMode {
            sampleTrips.remove(atOffsets: offsets)
        }
    }

    private func deleteCharges(at offsets: IndexSet) {
        for index in offsets {
            let session = displayedCharges[index]
            chargingTracker.deleteSession(session)
        }
        if vehicleData.isDemoMode {
            sampleCharges.remove(atOffsets: offsets)
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

            if sampleCharges.isEmpty {
                let c1 = ChargingSessionModel(
                    startTime: Date().addingTimeInterval(-43200),
                    startSocPct: 22.0,
                    locationName: "Ionity High Power Charger, Berlin",
                    latitude: 52.5200,
                    longitude: 13.4050
                )
                c1.endTime = Date().addingTimeInterval(-41400)
                c1.endSocPct = 80.0
                c1.totalKWhDelivered = 38.6
                c1.peakPowerKW = 100.2
                c1.averagePowerKW = 77.2

                let c2 = ChargingSessionModel(
                    startTime: Date().addingTimeInterval(-129600),
                    startSocPct: 45.0,
                    locationName: "Supercharger / Fastned, Hamburg",
                    latitude: 53.5511,
                    longitude: 9.9937
                )
                c2.endTime = Date().addingTimeInterval(-127800)
                c2.endSocPct = 85.0
                c2.totalKWhDelivered = 26.8
                c2.peakPowerKW = 88.5
                c2.averagePowerKW = 53.6

                sampleCharges = [c1, c2]
            }
        } else {
            sampleTrips.removeAll()
            sampleCharges.removeAll()
        }
    }
}

#Preview("Trip & Charging History View") {
    TripHistoryView(
        tripTracker: TripTrackingManager()
    )
    .environmentObject(VehicleDataManager())
    .environmentObject(ChargingTrackingManager())
}
