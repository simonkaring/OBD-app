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
    public let batteryHealth: BatteryHealthRecorder
    public let serviceReminder: ServiceReminderMonitor

    /// Owned here rather than created by the `WindowGroup` so that a CarPlay-only launch
    /// (no window scene, so `MainTabView.onAppear` never runs) still persists auto-recorded
    /// trips and charging sessions.
    public let modelContainer: ModelContainer
    @Published public private(set) var storageWarning: String?
    /// Non-fatal iCloud problem (for example a build without the iCloud entitlement), shown
    /// in Settings while history keeps saving locally.
    @Published public private(set) var syncWarning: String?

    private var cancellables = Set<AnyCancellable>()
    /// Widget/Live Activity writes are throttled separately from telemetry; the poll
    /// loop can publish several times per second.
    private var lastSharedPublish = Date.distantPast
    /// Units the last app-group snapshot was written with, so a preference change with
    /// no telemetry flowing still reaches the widget.
    private var lastPublishedUnits: SharedDisplayUnits?
    /// Battery health changes over months, so one daily sample is enough; this throttle keeps
    /// the fetch-and-save off the 1 Hz telemetry path.
    private var lastBatteryHealthCheck = Date.distantPast

    private static func makeModelContainer() -> (ModelContainer, String?, String?) {
        let schema = Schema(versionedSchema: VoltLinkCurrentSchema.versioned)
        // Pin the store to the app's own container. SwiftData's default URL resolves to the
        // first app group once the widget shares one, which would open an empty store and
        // orphan trips recorded before the widget was added.
        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        // CloudKit needs the iCloud capability and the identifiers in VoltLink.entitlements.
        // A free/personal signing profile has neither, so a failure here must fall back to
        // the same on-disk store instead of the in-memory one — losing persistent history
        // because sync could not start would be strictly worse than staying local.
        var syncWarning: String?
        if CloudSyncPreference.isEnabled() {
            let synced = ModelConfiguration(
                schema: schema, url: storeURL,
                cloudKitDatabase: .private(CloudSyncPreference.containerIdentifier))
            do {
                return (try ModelContainer(for: schema, configurations: synced), nil, nil)
            } catch {
                Logger(subsystem: "com.simonkaring.voltlink", category: "persistence")
                    .error("iCloud sync unavailable, staying on the local store: \(String(describing: error), privacy: .public)")
                syncWarning =
                    "iCloud sync could not start: \(error.localizedDescription). History keeps saving on this device; check that the build is signed with the iCloud capability."
            }
        }

        do {
            // Additive schema changes (V2's curve entity, V3's battery health entity) are
            // handled by SwiftData's inferred lightweight migration. Supplying a plan whose
            // versions share model classes made Core Data abort instead of migrate.
            return (try ModelContainer(for: schema, configurations: configuration), nil, syncWarning)
        } catch {
            // Surfaced in Console so a migration failure on a real device is diagnosable
            // rather than only visible as the in-app banner.
            Logger(subsystem: "com.simonkaring.voltlink", category: "persistence")
                .error("Persistent store unavailable, using in-memory history: \(String(describing: error), privacy: .public)")
            let warning =
                "Persistent history is unavailable: \(error.localizedDescription). New recordings are temporary and will be lost when VoltLink closes."
            do {
                return (
                    try ModelContainer(
                        for: schema,
                        configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)), warning, syncWarning
                )
            } catch {
                // Neither store opened. Name the cause in the crash report instead of
                // trapping blind, so a device failure is diagnosable.
                fatalError("VoltLink cannot start: \(error)")
            }
        }
    }

    public init(modelContainer: ModelContainer? = nil, connection: OBDConnectionProtocol? = nil) {
        if let modelContainer {
            self.modelContainer = modelContainer
            self.storageWarning = nil
            self.syncWarning = nil
        } else {
            (self.modelContainer, self.storageWarning, self.syncWarning) = Self.makeModelContainer()
        }
        let vData = VehicleDataManager(connection: connection)
        let locationManager = TripLocationManager()
        let tTracker = TripTrackingManager(locationManager: locationManager)
        let cTracker = ChargingTrackingManager(locationManager: locationManager)
        let dtc = DTCScannerService()

        self.vehicleData = vData
        self.tripTracker = tTracker
        self.chargingTracker = cTracker
        self.dtcService = dtc
        self.batteryHealth = BatteryHealthRecorder(context: self.modelContainer.mainContext)
        self.serviceReminder = ServiceReminderMonitor()

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
                self.recordBatteryHealthIfNeeded(snapshot: snapshot, vehicleData: vData)
                if let serviceDistance = snapshot.communityValues?[.serviceDistance] {
                    self.serviceReminder.observe(distanceKm: serviceDistance, vehicleName: vData.vehicleName)
                }
            }
            .store(in: &cancellables)

        // Re-evaluate freshness even when the adapter stops returning telemetry.
        // Observation replaced `objectWillChange`, so the one-second sweep is the
        // authoritative expiry clock.
        Timer.publish(every: 1, on: .main, in: .common).autoconnect().map { _ in () }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak vData, weak tTracker] _ in
                guard let self, let vData else { return }
                // Preferences are not part of the telemetry stream: switching to miles
                // while the adapter is idle would otherwise leave the widget and Live
                // Activity in km until telemetry resumes.
                if let lastPublishedUnits, lastPublishedUnits != self.currentUnits() {
                    self.publishSharedState(
                        snapshot: vData.latestTelemetry, vehicleData: vData, tripTracker: tTracker, force: true)
                }
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

    /// Stores at most one state-of-health reading per day for the connected vehicle. Demo
    /// mode is excluded so simulated 98.2% readings never pollute a real degradation curve.
    private func recordBatteryHealthIfNeeded(snapshot: TelemetrySnapshot, vehicleData: VehicleDataManager) {
        guard !vehicleData.isDemoMode, vehicleData.connectionState.isConnected else { return }
        let now = Date()
        guard now.timeIntervalSince(lastBatteryHealthCheck) >= 600 else { return }
        lastBatteryHealthCheck = now

        let soh = snapshot.stateOfHealthPct
        guard soh.isFinite, BatteryHealthRecorder.plausibleSOH.contains(soh) else { return }
        batteryHealth.record(
            sohPct: soh,
            socPct: snapshot.stateOfChargePct,
            batteryTempC: snapshot.batteryTempC,
            vehicleName: vehicleData.vehicleName,
            at: now)
    }

    /// The widget extension cannot read `UnitPreferences`, so mirror the user's choice.
    private func currentUnits() -> SharedDisplayUnits {
        let preferences = UnitPreferences.shared
        return SharedDisplayUnits(
            distance: preferences.distanceUnit == .miles ? .miles : .kilometers,
            power: preferences.powerUnit == .horsepower ? .horsepower : .kilowatts)
    }

    /// Mirrors the latest state into the app group for the widget and Live Activity.
    private func publishSharedState(
        snapshot: TelemetrySnapshot, vehicleData: VehicleDataManager, tripTracker: TripTrackingManager?, force: Bool = false
    ) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSharedPublish) >= 2 else { return }
        lastSharedPublish = now

        let soc = vehicleData.displayedTelemetry.stateOfChargePct
        let range = vehicleData.estimatedFullRangeKm.map { $0 * max(0, min(100, soc)) / 100 }
        // The Live Activity mirrors whichever recording is active; charging wins, matching
        // `LiveActivityCoordinator`.
        let activeSessionStartedAt = chargingTracker.currentSession?.startTime ?? tripTracker?.currentTrip?.startTime
        let units = currentUnits()
        lastPublishedUnits = units
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
            averageConsumptionKWhPer100Km: tripTracker?.averageConsumption,
            activeSessionStartedAt: activeSessionStartedAt,
            updatedAt: now,
            units: units
        )
        SharedTelemetryStore.save(shared)

        #if os(iOS)
        SharedWidgetRefresher.refreshIfNeeded(for: shared, at: now)
        LiveActivityCoordinator.shared.update(
            snapshot: shared,
            chargingActive: snapshot.isCharging,
            tripActive: tripTracker?.currentTrip != nil
        )
        #endif
    }
}
