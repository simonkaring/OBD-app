import SwiftUI
import Combine
import SwiftData
import OSLog

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
    /// Widget/Live Activity writes are throttled separately from telemetry; the poll
    /// loop can publish several times per second.
    private var lastSharedPublish = Date.distantPast

    private static func makeModelContainer() -> (ModelContainer, String?) {
        let schema = Schema(versionedSchema: VoltLinkCurrentSchema.versioned)
        // Pin the store to the app's own container. SwiftData's default URL resolves to the
        // first app group once the widget shares one, which would open an empty store and
        // orphan trips recorded before the widget was added.
        let configuration = ModelConfiguration(
            schema: schema,
            url: URL.applicationSupportDirectory.appending(path: "default.store"))
        do {
            // Schema V2 only adds an entity plus an empty-default relationship, so SwiftData's
            // inferred lightweight migration handles stores created by V1. Supplying a plan
            // whose two versions share model classes made Core Data abort instead of migrate.
            return (try ModelContainer(for: schema, configurations: configuration), nil)
        } catch {
            // Surfaced in Console so a migration failure on a real device is diagnosable
            // rather than only visible as the in-app banner.
            Logger(subsystem: "com.simonkaring.voltlink", category: "persistence")
                .error("Persistent store unavailable, using in-memory history: \(String(describing: error), privacy: .public)")
            let warning =
                "Persistent history is unavailable: \(error.localizedDescription). New recordings are temporary and will be lost when VoltLink closes."
            return (
                try! ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)), warning
            )
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

        // `Published` used to replay its current value on subscription; mirror that so
        // recorders start from the same initial snapshot after the Observation switch.
        let initialSnapshot = vData.latestTelemetry
        tTracker.processTelemetrySnapshot(
            initialSnapshot,
            vehicleName: vData.vehicleName,
            hasPowerData: vData.isDemoMode,
            requiresPowerForAutoStart: vData.supportedMetrics.contains(.power)
        )
        cTracker.processTelemetrySnapshot(initialSnapshot)

        vData.telemetryPublisher
            .sink { [weak self, weak tTracker, weak cTracker, weak vData] snapshot in
                let hasPower = vData?.isDemoMode == true || (vData?.liveMetrics.contains(.power) == true && snapshot.hasFreshPower)
                tTracker?.processTelemetrySnapshot(
                    snapshot, vehicleName: vData?.vehicleName ?? "Vehicle", hasPowerData: hasPower,
                    requiresPowerForAutoStart: vData?.supportedMetrics.contains(.power) == true)
                cTracker?.processTelemetrySnapshot(snapshot)
                guard let self, let vData else { return }
                self.publishSharedState(snapshot: snapshot, vehicleData: vData, tripTracker: tTracker)
            }
            .store(in: &cancellables)

        // Re-evaluate freshness even when the adapter stops returning telemetry.
        // Observation replaced `objectWillChange`, so the one-second sweep is the
        // authoritative expiry clock.
        Timer.publish(every: 1, on: .main, in: .common).autoconnect().map { _ in () }
            .receive(on: DispatchQueue.main)
            .sink { [weak vData] _ in
                guard let vData else { return }
                vData.expireExternalSpeed()
                if case .ready = vData.connectionState, vData.hasSelectedVehicle,
                    !vData.isDemoMode, vData.needsExternalSpeed()
                {
                    locationManager.startSpeedMonitoring()
                } else {
                    locationManager.stopSpeedMonitoring()
                    vData.clearExternalSpeed()
                }
            }
            .store(in: &cancellables)

        // Only warn about a dropped adapter while a trip is actually being recorded;
        // disconnects while idle are expected and already shown by the banner.
        vData.onUnexpectedDisconnect = { [weak tTracker] in
            guard tTracker?.currentTrip != nil else { return }
            #if os(iOS)
            NotificationService.shared.notifyAdapterDisconnected()
            #endif
        }

        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { location in
                guard location.speed >= 0,
                    vData.hasSelectedVehicle,
                    vData.connectionState.isConnected,
                    !vData.isDemoMode
                else { return }
                vData.applyExternalSpeed(location.speed * 3.6, timestamp: location.timestamp)
            }
            .store(in: &cancellables)
    }

    /// Mirrors the latest state into the app group for the widget and Live Activity.
    private func publishSharedState(snapshot: TelemetrySnapshot, vehicleData: VehicleDataManager, tripTracker: TripTrackingManager?) {
        let now = Date()
        guard now.timeIntervalSince(lastSharedPublish) >= 2 else { return }
        lastSharedPublish = now

        let soc = vehicleData.displayedTelemetry.stateOfChargePct
        let range = vehicleData.estimatedFullRangeKm.map { $0 * max(0, min(100, soc)) / 100 }
        let shared = SharedTelemetrySnapshot(
            vehicleName: vehicleData.vehicleName,
            socPct: soc,
            powerKW: snapshot.isCharging ? snapshot.chargePowerKW : abs(snapshot.powerKW),
            speedKmH: snapshot.speedKmH,
            rangeKm: range,
            isCharging: snapshot.isCharging,
            isConnected: vehicleData.connectionState.isConnected || vehicleData.isDemoMode,
            isDemoMode: vehicleData.isDemoMode,
            isTripActive: tripTracker?.currentTrip != nil,
            distanceKm: tripTracker?.currentTrip?.distanceKm ?? 0,
            updatedAt: now
        )
        SharedTelemetryStore.save(shared)

        #if os(iOS)
        SharedWidgetRefresher.refreshIfNeeded(at: now)
        LiveActivityCoordinator.shared.update(
            snapshot: shared,
            chargingActive: snapshot.isCharging,
            tripActive: tripTracker?.currentTrip != nil
        )
        #endif
    }
}
