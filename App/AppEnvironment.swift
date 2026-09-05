import SwiftUI
import Combine
import SwiftData

public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()

    public let vehicleData: VehicleDataManager
    public let tripTracker: TripTrackingManager
    public let chargingTracker: ChargingTrackingManager
    public let dtcService: DTCScannerService

    /// Owned here rather than created by the `WindowGroup` so that a CarPlay-only launch
    /// (no window scene, so `MainTabView.onAppear` never runs) still persists auto-recorded
    /// trips and charging sessions.
    public let modelContainer: ModelContainer

    private var cancellables = Set<AnyCancellable>()

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([TripModel.self, TelemetryPointModel.self, ChargingSessionModel.self, SavedDTCModel.self])
        if let container = try? ModelContainer(for: schema) {
            return container
        }
        // Last resort: run unpersisted rather than crashing on a corrupt/unwritable store.
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    public init() {
        self.modelContainer = Self.makeModelContainer()
        let vData = VehicleDataManager()
        let locationManager = TripLocationManager()
        let tTracker = TripTrackingManager(locationManager: locationManager)
        let cTracker = ChargingTrackingManager(locationManager: locationManager)
        let dtc = DTCScannerService()

        self.vehicleData = vData
        self.tripTracker = tTracker
        self.chargingTracker = cTracker
        self.dtcService = dtc

        // `mainContext` is the same context SwiftUI's `@Query` reads from, so recorded
        // trips/sessions show up in the UI without a second context to reconcile.
        let container = self.modelContainer
        DispatchQueue.main.async {
            tTracker.modelContext = container.mainContext
            cTracker.modelContext = container.mainContext
        }

        vData.$latestTelemetry
            .sink { [weak tTracker, weak cTracker, weak vData] snapshot in
                tTracker?.processTelemetrySnapshot(snapshot, vehicleName: vData?.vehicleName ?? "Mercedes EQA 250")
                cTracker?.processTelemetrySnapshot(snapshot)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(vData.$connectionState, vData.$selectedProfileID, vData.$isDemoMode)
            .sink { state, profileID, isDemo in
                if case .ready = state, profileID == .mercedesEQA250, !isDemo {
                    locationManager.startSpeedMonitoring()
                } else {
                    locationManager.stopSpeedMonitoring()
                    vData.clearExternalSpeed()
                }
            }
            .store(in: &cancellables)

        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { location in
                guard location.speed >= 0,
                      vData.selectedProfileID == .mercedesEQA250,
                      vData.connectionState.isConnected,
                      !vData.isDemoMode else { return }
                vData.applyExternalSpeed(location.speed * 3.6, timestamp: location.timestamp)
            }
            .store(in: &cancellables)
    }
}
