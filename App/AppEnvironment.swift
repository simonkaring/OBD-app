import SwiftUI
import Combine
import SwiftData

@MainActor
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
    @Published public private(set) var storageWarning: String?

    private var cancellables = Set<AnyCancellable>()

    private static func makeModelContainer() -> (ModelContainer, String?) {
        let schema = Schema([TripModel.self, TelemetryPointModel.self, ChargingSessionModel.self, SavedDTCModel.self])
        do {
            return (try ModelContainer(for: schema), nil)
        } catch {
            let warning = "Persistent history is unavailable: \(error.localizedDescription). New recordings are temporary and will be lost when VoltLink closes."
            return (try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)), warning)
        }
    }

    public init(modelContainer: ModelContainer? = nil, connection: OBDConnectionProtocol? = nil) {
        (self.modelContainer, self.storageWarning) = modelContainer.map { ($0, nil) } ?? Self.makeModelContainer()
        let vData = VehicleDataManager(connection: connection)
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
        tTracker.modelContext = self.modelContainer.mainContext
        cTracker.modelContext = self.modelContainer.mainContext

        vData.prepareDemoModeChange = { [weak vData, weak tTracker, weak cTracker] enabled in
            guard let vData, let tTracker, let cTracker else { return false }
            let soc = vData.latestTelemetry.stateOfChargePct
            // Save both real recordings before switching either manager to transient data.
            guard tTracker.stopTrip(endSoc: soc), cTracker.stopSession(endSoc: soc) else { return false }
            return tTracker.setDemoMode(enabled, endSoc: soc) && cTracker.setDemoMode(enabled, endSoc: soc)
        }

        vData.$latestTelemetry
            .sink { [weak tTracker, weak cTracker, weak vData] snapshot in
                let hasPower = vData?.isDemoMode == true || (vData?.liveMetrics.contains(.power) == true && snapshot.hasFreshPower)
                tTracker?.processTelemetrySnapshot(snapshot, vehicleName: vData?.vehicleName ?? "Mercedes EQA 250", hasPowerData: hasPower, requiresPowerForAutoStart: vData?.supportedMetrics.contains(.power) == true)
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
