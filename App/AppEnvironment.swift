import SwiftUI
import Combine

public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()

    @Published public var vehicleData: VehicleDataManager
    @Published public var tripTracker: TripTrackingManager
    @Published public var chargingTracker: ChargingTrackingManager
    @Published public var dtcService: DTCScannerService
    private var cancellables = Set<AnyCancellable>()

    public init() {
        let vData = VehicleDataManager()
        let locationManager = TripLocationManager()
        let tTracker = TripTrackingManager(locationManager: locationManager)
        let cTracker = ChargingTrackingManager(locationManager: locationManager)
        let dtc = DTCScannerService()

        self.vehicleData = vData
        self.tripTracker = tTracker
        self.chargingTracker = cTracker
        self.dtcService = dtc

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
