import SwiftUI
import Combine

public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()

    @Published public var vehicleData: VehicleDataManager
    @Published public var tripTracker: TripTrackingManager
    @Published public var dtcService: DTCScannerService

    public init() {
        let vData = VehicleDataManager()
        let tTracker = TripTrackingManager()
        let dtc = DTCScannerService()

        self.vehicleData = vData
        self.tripTracker = tTracker
        self.dtcService = dtc
    }
}
