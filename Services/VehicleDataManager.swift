import Foundation
import Combine
import Observation
import SwiftUI

@MainActor
@Observable
public final class VehicleDataManager: OBDConnectionDelegate {
    public static let selectedVehicleIDDefaultsKey = "selectedVehicleID"
    public static let selectedModelYearDefaultsKey = "selectedModelYear"

    public private(set) var latestTelemetry = TelemetrySnapshot()
    public private(set) var connectionState: BLEConnectionState = .disconnected
    public private(set) var selectedProfile: VehicleProfile = MercedesEQA250Profile()
    public private(set) var selectedProfileID: VehicleProfileID = .mercedesEQA250
    public private(set) var selectedVehicle = VehicleCatalog.defaultModel
    public private(set) var selectedModelYear: Int?
    public private(set) var chargingSession = ChargingSessionState()
    public var isDemoMode: Bool = false
    public private(set) var isCalibrating: Bool = false
    public private(set) var calibrationProgress: Double = 0.0
    public private(set) var calibratedCommands: [String]? = nil
    public private(set) var calibrationSummary: String? = nil
    public private(set) var liveMetrics: Set<TelemetryMetric> = []
    public private(set) var isCommandSessionActive = false
    public private(set) var socReferenceOffset: Double?
    public private(set) var hasSelectedVehicle: Bool = false

    /// Non-UI consumers (trip/charging recorders, CarPlay) need an event stream; SwiftUI
    /// observes the individual properties above through Observation instead of this.
    @ObservationIgnored public let telemetryPublisher = PassthroughSubject<TelemetrySnapshot, Never>()

    public var obdConnection: OBDConnectionProtocol
    /// Close recordings before changing their source. A failed save keeps the current mode.
    public var prepareDemoModeChange: ((Bool) -> Bool)?
    public let chargingTracker = ChargingSessionTracker()

    public var vehicleName: String {
        selectedVehicle.fullName + (selectedModelYear.map { " (\($0))" } ?? "")
    }
    public var usableBatteryCapacityKWh: Double {
        // A shared decoder's reference pack size is not the selected variant's capacity.
        selectedVehicle.batteryCapacityKWh
    }
    public var estimatedFullRangeKm: Double? {
        selectedVehicle.estimatedRangeKm
    }

    public var hasChargePower: Bool {
        isDemoMode || latestTelemetry.chargePowerUpdatedAt != nil
    }

    @ObservationIgnored private var isInitializing = false
    @ObservationIgnored private var shouldPollAfterInitialization = false
    @ObservationIgnored private var pollingGeneration = 0
    @ObservationIgnored private var chargingEstimator = ChargingPowerEstimator()
    @ObservationIgnored private var commandMetrics: [String: Set<TelemetryMetric>] = [:]
    @ObservationIgnored private var commandMisses: [String: Int] = [:]
    @ObservationIgnored private var externalSpeedUpdatedAt: Date?
    @ObservationIgnored private var obdSpeedUpdatedAt: Date?
    @ObservationIgnored private var explicitChargingStatus: (charging: Bool, timestamp: Date)?
    @ObservationIgnored private var batchedSnapshot: TelemetrySnapshot?
    @ObservationIgnored private let persistenceDefaults: UserDefaults?
    @ObservationIgnored private lazy var pollingLoop: TelemetryPollingLoop = makePollingLoop()

    private var isPolling: Bool { pollingLoop.isRunning }

    public var supportedMetrics: Set<TelemetryMetric> {
        if isDemoMode { return Set(TelemetryMetric.allCases).subtracting(TelemetryMetric.eqaCommunityMetrics) }
        var metrics = selectedProfile.supportedMetrics
        // GPS can supply speed even when the vehicle has no usable speed PID.
        metrics.insert(.speed)
        if metrics.contains(.power) { metrics.insert(.tripAverageConsumption) }
        return TelemetryMetric.includingDerivedMetrics(metrics)
    }

    public init(connection: OBDConnectionProtocol? = nil, userDefaults: UserDefaults? = nil) {
        if let userDefaults {
            self.persistenceDefaults = userDefaults
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName.localizedCaseInsensitiveContains("xctest")
        {
            self.persistenceDefaults = nil
        } else {
            self.persistenceDefaults = .standard
        }

        if let selectedVehicleID = persistenceDefaults?.string(forKey: Self.selectedVehicleIDDefaultsKey),
            let restoredVehicle = VehicleCatalog.allModels.first(where: { $0.id == selectedVehicleID })
        {
            self.selectedVehicle = restoredVehicle
            self.selectedProfileID = restoredVehicle.profileID
            self.selectedProfile = restoredVehicle.profileID.makeProfile()
            if let year = persistenceDefaults?.object(forKey: Self.selectedModelYearDefaultsKey) as? Int,
                restoredVehicle.modelYears().contains(year)
            {
                self.selectedModelYear = year
            }
            self.hasSelectedVehicle = true
        }

        if let conn = connection {
            self.obdConnection = conn
        } else {
            self.obdConnection = BluetoothManager()
        }
        self.obdConnection.delegate = self
        loadSOCReference()
    }

    private var socReferenceStore: SOCReferenceStore {
        SOCReferenceStore(
            defaults: persistenceDefaults,
            vehicleID: selectedVehicle.id,
            modelYear: selectedModelYear,
            profileID: selectedProfileID)
    }

    private func loadSOCReference() {
        socReferenceOffset = socReferenceStore.load()
    }

    public func canSetSOCReference(at date: Date = .now) -> Bool {
        guard !isDemoMode, case .ready = connectionState, liveMetrics.contains(.soc),
            let updatedAt = latestTelemetry.socUpdatedAt
        else { return false }
        return (0...15).contains(date.timeIntervalSince(updatedAt))
    }

    @MainActor
    @discardableResult
    public func setSOCReference(_ dashboardSOC: Double) -> Bool {
        guard dashboardSOC.isFinite, (0...100).contains(dashboardSOC), canSetSOCReference() else { return false }
        socReferenceOffset = dashboardSOC - latestTelemetry.stateOfChargePct
        if let offset = socReferenceOffset { socReferenceStore.save(offset) }
        return true
    }

    @MainActor
    public func resetSOCReference() {
        socReferenceOffset = nil
        socReferenceStore.reset()
    }

    public var displayedTelemetry: TelemetrySnapshot { telemetryForDisplay(latestTelemetry) }

    /// Apply the dashboard reference only at presentation time. Recordings and SOC-slope
    /// charging estimates continue to use the original readings, including near 0/100%.
    public func telemetryForDisplay(_ snapshot: TelemetrySnapshot) -> TelemetrySnapshot {
        guard !isDemoMode, liveMetrics.contains(.soc), snapshot.socUpdatedAt != nil,
            let offset = socReferenceOffset
        else { return snapshot }
        var displayed = snapshot
        displayed.stateOfChargePct = min(100, max(0, snapshot.stateOfChargePct + offset))
        return displayed
    }

    /// Express a recorded (raw) SoC reading on the same scale as the battery bar, which may
    /// be offset by a dashboard reference. Recordings stay raw; only presentation shifts.
    public func displayedSOC(fromRaw raw: Double) -> Double {
        guard !isDemoMode, liveMetrics.contains(.soc), latestTelemetry.socUpdatedAt != nil,
            let offset = socReferenceOffset
        else { return raw }
        return min(100, max(0, raw + offset))
    }

    public func toggleDemoMode(_ enabled: Bool) {
        guard !isCommandSessionActive, enabled != isDemoMode, prepareDemoModeChange?(enabled) ?? true else { return }
        stopPolling()
        obdConnection.delegate = nil
        obdConnection.disconnect()
        publishTelemetry(TelemetrySnapshot())
        resetTelemetryValidity()
        isDemoMode = enabled
        if enabled {
            stopPolling()
            let mock = MockOBDAdapter()
            self.obdConnection = mock
            self.obdConnection.delegate = self
            connectionState = .demoMode
        } else {
            let ble = BluetoothManager()
            self.obdConnection = ble
            self.obdConnection.delegate = self
            connectionState = .disconnected
            publishTelemetry(TelemetrySnapshot())
            resetTelemetryValidity()
            stopPolling()
        }
    }

    public func clearDemoData() {
        publishTelemetry(TelemetrySnapshot())
        chargingEstimator.reset()
        if let mock = obdConnection as? MockOBDAdapter {
            mock.simulationEngine.scenario = .cityDriving
            mock.simulationEngine.injectedFaultCode = nil
            mock.simulationEngine.userSpeedOverride = nil
            mock.simulationEngine.userThrottleOverride = nil
            mock.simulationEngine.userRegenOverride = nil
        }
    }

    public func selectProfile(_ id: VehicleProfileID) {
        guard !isCommandSessionActive else { return }
        let wasPolling = isPolling
        stopPolling()
        selectedProfileID = id
        selectedProfile = id.makeProfile()
        loadSOCReference()
        calibratedCommands = nil
        calibrationSummary = nil
        pollingLoop.resetIndex()
        chargingEstimator.reset()
        resetTelemetryValidity()
        if !isDemoMode, obdConnection.state.isConnected {
            initializeProfile(resumePolling: wasPolling)
        }
    }

    @discardableResult
    public func selectVehicle(_ vehicle: VehicleModelEntry, modelYear: Int? = nil) -> Bool {
        guard !isCommandSessionActive,
            modelYear.map({ vehicle.modelYears().contains($0) }) ?? true
        else { return false }
        selectedVehicle = vehicle
        selectedModelYear = modelYear
        selectProfile(vehicle.profileID)
        persistenceDefaults?.set(vehicle.id, forKey: Self.selectedVehicleIDDefaultsKey)
        if let modelYear {
            persistenceDefaults?.set(modelYear, forKey: Self.selectedModelYearDefaultsKey)
        } else {
            persistenceDefaults?.removeObject(forKey: Self.selectedModelYearDefaultsKey)
        }
        hasSelectedVehicle = true
        return true
    }

    public func startCalibration() {
        guard !isCalibrating, !isInitializing, !isCommandSessionActive else { return }
        let wasPolling = isPolling
        stopPolling()
        isCalibrating = true
        calibrationProgress = 0.0
        calibrationSummary = nil

        let commandsToTest = selectedProfile.pollingCommands
        let generation = pollingGeneration
        guard !commandsToTest.isEmpty else {
            isCalibrating = false
            if wasPolling { startPolling() }
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var verifiedCommands: [String] = []
            let total = commandsToTest.count

            for (index, cmd) in commandsToTest.enumerated() {
                guard self.isCalibrating, generation == self.pollingGeneration else { return }
                let raw = await self.sendOBDCommandAsync(cmd)
                guard self.isCalibrating, generation == self.pollingGeneration else { return }

                if self.isSupportedResponse(command: cmd, rawResponse: raw) {
                    verifiedCommands.append(cmd)
                    let updates = self.selectedProfile.parseResponses(command: cmd, rawResponse: raw)
                    let applied = self.applyUpdates(updates, timestamp: .now, sourceCommand: cmd)
                    if !applied {
                        self.recordMiss(for: cmd)
                    }
                }
                self.calibrationProgress = Double(index + 1) / Double(total)
            }

            let respondingReadCount = verifiedCommands.filter { !$0.uppercased().hasPrefix("AT") }.count
            if respondingReadCount > 0 {
                self.calibratedCommands = self.selectedProfile.retainUnverifiedPollingCommands ? nil : verifiedCommands
                let totalReadCount = commandsToTest.filter { !$0.uppercased().hasPrefix("AT") }.count
                self.calibrationSummary = "\(respondingReadCount) of \(totalReadCount) reads responded"
            } else {
                self.calibratedCommands = nil
                self.calibrationSummary = "No reads responded"
            }
            self.pollingLoop.resetIndex()
            self.isCalibrating = false
            if wasPolling || self.obdConnection.state.isConnected {
                self.startPolling()
            }
        }
    }

    public func resetCalibration() {
        calibratedCommands = nil
        calibrationSummary = nil
    }

    private func sendOBDCommandAsync(_ command: String) async -> String {
        switch await sendCommandResult(command) {
        case .success(let raw): return raw
        case .failure: return ""
        }
    }

    private func isSupportedResponse(command: String, rawResponse: String) -> Bool {
        let clean = ISO15765Parser().cleanELMResponse(rawResponse)
        if clean.isEmpty { return false }

        let upper = clean.uppercased()
        let negativeMarkers = ["NO DATA", "ERROR", "UNABLE TO CONNECT", "BUS INIT", "CAN ERROR", "?", "STOPPED"]
        if negativeMarkers.contains(where: { upper.contains($0) }) {
            return false
        }

        if command.uppercased().hasPrefix("AT") {
            let lines = upper.components(separatedBy: .newlines).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if command.replacingOccurrences(of: " ", with: "").uppercased() == "ATZ" {
                return lines.contains { !$0.isEmpty && $0.replacingOccurrences(of: " ", with: "") != "ATZ" }
            }
            return lines.contains("OK")
        }

        if !selectedProfile.parseResponses(command: command, rawResponse: rawResponse).isEmpty {
            return true
        }

        let payload = ISO15765Parser().assembleISOTPPayload(rawResponse)
        if !payload.isEmpty && !payload.hasPrefix("7F") {
            if payload.hasPrefix("62") || payload.hasPrefix("41") {
                return true
            }
        }

        return false
    }

    public func startPolling() {
        guard !isDemoMode, !isCommandSessionActive else { return }
        if isInitializing {
            shouldPollAfterInitialization = true
            return
        }
        pollingLoop.start()
    }

    public func stopPolling() {
        pollingLoop.stop()
        isInitializing = false
        shouldPollAfterInitialization = false
        isCalibrating = false
        pollingGeneration += 1
        chargingEstimator.reset()
        invalidateEstimatedChargingPower()
    }

    private func makePollingLoop() -> TelemetryPollingLoop {
        let loop = TelemetryPollingLoop()
        loop.commands = { [weak self] in
            guard let self else { return [] }
            return self.calibratedCommands ?? self.selectedProfile.pollingCommands
        }
        loop.isConnected = { [weak self] in
            self?.obdConnection.state.isConnected ?? false
        }
        loop.send = { [weak self] command in
            guard let self else {
                return .failure(NSError(domain: "VehicleDataManager", code: -1))
            }
            return await self.sendCommandResult(command)
        }
        loop.handleRead = { [weak self] command, raw in
            guard let self else { return false }
            let updates = self.selectedProfile.parseResponses(command: command, rawResponse: raw)
            let applied = self.applyUpdates(updates, timestamp: .now, sourceCommand: command)
            if !applied { self.recordMiss(for: command) }
            self.expireExternalSpeed()
            self.expireEstimatedChargingPower(at: .now)
            return applied
        }
        loop.handleReadFailure = { [weak self] command in
            self?.recordMiss(for: command)
            self?.expireExternalSpeed()
            self?.expireEstimatedChargingPower(at: .now)
        }
        loop.handleControl = { [weak self] command, result in
            guard let self, case .success(let raw) = result else { return false }
            return self.isSupportedResponse(command: command, rawResponse: raw)
        }
        loop.handleControlFailure = { [weak self] command in
            self?.handleRoutingFailure(at: command)
        }
        return loop
    }

    private func handleRoutingFailure(at command: String) {
        pollingLoop.stop()
        resetTelemetryValidity()
        obdConnection.disconnect()
        connectionState = .error("Adapter routing failed at \(command). Reconnect the scanner.")
    }

    private func sendCommandResult(_ command: String) async -> Result<String, Error> {
        await withCheckedContinuation { continuation in
            obdConnection.sendCommand(command) { continuation.resume(returning: $0) }
        }
    }

    public func beginCommandSession() -> Bool {
        guard !isCommandSessionActive, !isInitializing, !isCalibrating,
            obdConnection.state.isConnected
        else { return false }
        stopPolling()
        pollingLoop.resetIndex()
        isCommandSessionActive = true
        return true
    }

    public func endCommandSession(restoreProfile: Bool = true) {
        isCommandSessionActive = false
        guard !isDemoMode, obdConnection.state.isConnected else { return }
        if restoreProfile { initializeProfile() } else { startPolling() }
    }

    func applyUpdate(_ update: TelemetryUpdate) {
        applyUpdate(update, timestamp: .now, sourceCommand: nil)
    }

    func applyUpdate(_ update: TelemetryUpdate, timestamp: Date) {
        applyUpdate(update, timestamp: timestamp, sourceCommand: nil)
    }

    func applyExternalSpeed(_ speedKmH: Double, timestamp: Date = .now) {
        guard !isDemoMode, (0...15).contains(Date.now.timeIntervalSince(timestamp)),
            needsExternalSpeed(at: timestamp)
        else { return }
        applyUpdate(.speed(speedKmH), timestamp: timestamp, sourceCommand: nil, isExternalSpeed: true)
    }

    func needsExternalSpeed(at date: Date = .now) -> Bool {
        guard let obdSpeedUpdatedAt else { return true }
        return !(0...15).contains(date.timeIntervalSince(obdSpeedUpdatedAt))
    }

    public func clearExternalSpeed() {
        guard externalSpeedUpdatedAt != nil else { return }
        externalSpeedUpdatedAt = nil
        latestTelemetry.speedKmH = 0
        latestTelemetry.speedUpdatedAt = nil
        if liveMetrics.contains(.speed) { liveMetrics.remove(.speed) }
        liveMetrics = TelemetryMetric.includingDerivedMetrics(liveMetrics)
        // Keep non-UI consumers in sync with the same in-place mutation that used to
        // produce an `objectWillChange` notification.
        telemetryPublisher.send(latestTelemetry)
    }

    /// Physically plausible bounds per decoded quantity. Kept as a forwarding shim so
    /// existing call sites and tests continue to use the manager's namespace.
    static func isPlausible(_ update: TelemetryUpdate) -> Bool {
        TelemetryPlausibility.isPlausible(update)
    }

    @discardableResult
    private func applyUpdate(_ update: TelemetryUpdate, timestamp: Date, sourceCommand: String?, isExternalSpeed: Bool = false) -> Bool {
        guard Self.isPlausible(update) else {
            return false
        }
        var snap = batchedSnapshot ?? latestTelemetry
        snap.timestamp = timestamp
        if let socAt = snap.socUpdatedAt, timestamp.timeIntervalSince(socAt) > 15 {
            chargingEstimator.clear(snapshot: &snap)
            chargingEstimator.reset()
        }
        var updatedMetrics = metrics(for: update)
        switch update {
        case .speed(let s):
            guard snap.speedUpdatedAt.map({ timestamp >= $0 }) ?? true else { return false }
            if isExternalSpeed {
                externalSpeedUpdatedAt = timestamp
            } else {
                obdSpeedUpdatedAt = timestamp
                externalSpeedUpdatedAt = nil
            }
            snap.speedKmH = s
            snap.speedUpdatedAt = timestamp
            if s > 1.0 {
                chargingEstimator.clear(snapshot: &snap)
                chargingEstimator.reset()
                // If moving, we cannot be plugged in and charging
                snap.isCharging = false
                snap.chargePowerKW = 0.0
            }

        case .power(let v, let a, let kw):
            chargingEstimator.clear(snapshot: &snap)
            snap.voltageV = v
            snap.currentA = a
            snap.powerKW = kw
            snap.voltageUpdatedAt = timestamp
            snap.currentUpdatedAt = timestamp
            snap.powerUpdatedAt = timestamp
            // Negative pack current = energy into the battery. Only treat it as
            // charging (not regen) when parked, since regen only occurs while moving.
            if a < -1.0 && chargingPermitted(snapshot: snap) {
                snap.isCharging = true
                snap.chargePowerKW = abs(kw)
                snap.chargePowerUpdatedAt = snap.timestamp
            } else {
                snap.isCharging = false
                snap.chargePowerKW = 0.0
                snap.chargePowerUpdatedAt = snap.timestamp
            }
            snap.chargePowerSource = .measured
            snap.chargePowerUpdatedAt = timestamp

        case .packVoltage(let v):
            snap.voltageV = v
            snap.voltageUpdatedAt = timestamp
            updatePackPower(snapshot: &snap, updatedMetrics: &updatedMetrics)

        case .packCurrent(let current):
            snap.currentA = current
            snap.currentUpdatedAt = timestamp
            updatePackPower(snapshot: &snap, updatedMetrics: &updatedMetrics)

        case .soc(let soc):
            snap.stateOfChargePct = soc
            snap.socUpdatedAt = snap.timestamp
            updateEstimatedChargingPower(soc: soc, snapshot: &snap)

        case .soh(let soh): snap.stateOfHealthPct = soh
        case .batteryTemp(let min, let max, let avg):
            snap.batteryTempC = avg
            snap.batteryTempMinC = min
            snap.batteryTempMaxC = max
        case .aux12V(let v): snap.aux12VVolts = v
        case .motorStats(let rpm, let torque):
            snap.motorRpm = rpm
            snap.motorTorqueNm = torque
        case .hvacPower(let kw): snap.hvacPowerKW = kw
        case .chargingStats(let kw, _):
            explicitChargingStatus = (kw.map { $0 > 0.5 } ?? true, timestamp)
            if let kw {
                snap.isCharging = kw > 0.5
                snap.chargePowerKW = kw
                snap.chargePowerUpdatedAt = snap.timestamp
                snap.chargePowerSource = .measured
            } else {
                // Status bit says "charging" but the profile can't measure the rate. Flag
                // it and let the SoC-slope estimator or a pack-power PID fill in the kW.
                snap.isCharging = true
            }
        case .fuelLevel(let pct): snap.fuelLevelPct = pct
        case .throttlePosition(let pct): snap.throttlePositionPct = pct
        case .engineLoad(let pct): snap.engineLoadPct = pct
        case .coolantTemp(let c): snap.coolantTempC = c
        case .intakeAirTemp(let c): snap.intakeAirTempC = c
        case .ambientAirTemp(let c): snap.ambientAirTempC = c
        case .maf(let g): snap.mafGramsPerSec = g
        case .manifoldPressure(let kPa): snap.manifoldPressureKPa = kPa
        case .oilTemp(let c): snap.oilTempC = c
        case .timingAdvance(let deg): snap.timingAdvanceDeg = deg
        case .barometricPressure(let kPa): snap.barometricPressureKPa = kPa
        case .vehicleRange(let km):
            snap.vehicleRangeKm = km
            snap.vehicleRangeUpdatedAt = timestamp
        case .communityMetric(let metric, let value):
            if snap.communityValues == nil { snap.communityValues = [:] }
            snap.communityValues?[metric] = value
        case .genericPid: break
        }
        if !chargingPermitted(snapshot: snap) {
            snap.isCharging = false
            snap.chargePowerKW = 0
            if snap.chargePowerSource == .socEstimate { chargingEstimator.clear(snapshot: &snap) }
        }
        let available = TelemetryMetric.includingDerivedMetrics(liveMetrics.union(updatedMetrics))
        if available != liveMetrics { liveMetrics = available }
        if let sourceCommand {
            commandMetrics[sourceCommand, default: []].formUnion(updatedMetrics)
            commandMisses[sourceCommand] = 0
        }
        if batchedSnapshot != nil {
            batchedSnapshot = snap
        } else {
            publishTelemetry(snap)
            updateChargingSession(snap)
        }
        return true
    }

    @discardableResult
    func applyUpdates(_ updates: [TelemetryUpdate], timestamp: Date, sourceCommand: String? = nil) -> Bool {
        batchedSnapshot = latestTelemetry
        let applied = updates.reduce(false) { applyUpdate($1, timestamp: timestamp, sourceCommand: sourceCommand) || $0 }
        let snapshot = batchedSnapshot!
        batchedSnapshot = nil
        if applied {
            publishTelemetry(snapshot)
            updateChargingSession(snapshot)
        }
        return applied
    }

    private func chargingPermitted(snapshot: TelemetrySnapshot) -> Bool {
        if snapshot.hasFreshSpeed && snapshot.speedKmH >= 1 { return false }
        if let status = explicitChargingStatus, abs(snapshot.timestamp.timeIntervalSince(status.timestamp)) <= 15 {
            return status.charging
        }
        return snapshot.hasFreshSpeed && snapshot.speedKmH < 1
    }

    private func publishTelemetry(_ snapshot: TelemetrySnapshot) {
        latestTelemetry = snapshot
        telemetryPublisher.send(snapshot)
    }

    private func updateChargingSession(_ snap: TelemetrySnapshot) {

        // Update live charging session tracker
        let currentPower = snap.isCharging ? snap.chargePowerKW : nil
        self.chargingSession = chargingTracker.update(
            soc: snap.stateOfChargePct,
            packVoltage: snap.voltageV,
            // A genuine 0 A reading (idle pack) is data, not "no data" — key off whether
            // pack current has ever decoded rather than off a 0.0 sentinel.
            packCurrent: liveMetrics.contains(.packCurrent) ? snap.currentA : nil,
            powerKW: currentPower,
            vehicleBatteryCapacityKWh: usableBatteryCapacityKWh,
            isStationary: snap.isCharging
        )
    }

    private func updatePackPower(snapshot: inout TelemetrySnapshot, updatedMetrics: inout Set<TelemetryMetric>) {
        let available = liveMetrics.union(updatedMetrics)
        guard available.contains(.packVoltage), available.contains(.packCurrent),
            let voltageAt = snapshot.voltageUpdatedAt, let currentAt = snapshot.currentUpdatedAt,
            (0...15).contains(snapshot.timestamp.timeIntervalSince(voltageAt)),
            (0...15).contains(snapshot.timestamp.timeIntervalSince(currentAt))
        else { return }
        chargingEstimator.clear(snapshot: &snapshot)
        snapshot.powerKW = (snapshot.voltageV * snapshot.currentA) / 1000.0
        // Power is only as fresh as its oldest input.
        snapshot.powerUpdatedAt = min(voltageAt, currentAt)
        updatedMetrics.insert(.power)
        if snapshot.currentA < -1.0 && chargingPermitted(snapshot: snapshot) {
            snapshot.isCharging = true
            snapshot.chargePowerKW = abs(snapshot.powerKW)
        } else {
            snapshot.isCharging = false
            snapshot.chargePowerKW = 0
        }
        snapshot.chargePowerUpdatedAt = snapshot.timestamp
        snapshot.chargePowerSource = .measured
    }

    private func metrics(for update: TelemetryUpdate) -> Set<TelemetryMetric> {
        switch update {
        case .speed: [.speed]
        case .power: [.power, .packVoltage, .packCurrent]
        case .packVoltage: [.packVoltage]
        case .packCurrent: [.packCurrent]
        case .soc: [.soc]
        case .soh: [.soh]
        case .batteryTemp: [.batteryTemp, .batteryTempMin, .batteryTempMax]
        case .aux12V: [.aux12V]
        case .motorStats: [.motorRpm, .motorTorque]
        case .fuelLevel: [.fuelLevel]
        case .throttlePosition: [.throttlePosition]
        case .engineLoad: [.engineLoad]
        case .coolantTemp: [.coolantTemp]
        case .intakeAirTemp: [.intakeAirTemp]
        case .ambientAirTemp: [.ambientAirTemp]
        case .maf: [.maf]
        case .manifoldPressure: [.manifoldPressure]
        case .oilTemp: [.oilTemp]
        case .timingAdvance: [.timingAdvance]
        case .barometricPressure: [.barometricPressure]
        case .vehicleRange: [.vehicleRange]
        case .communityMetric(let metric, _): [metric]
        case .hvacPower, .chargingStats, .genericPid: []
        }
    }

    private func recordMiss(for command: String) {
        guard var metrics = commandMetrics[command] else { return }
        commandMisses[command, default: 0] += 1
        guard commandMisses[command, default: 0] >= 3 else { return }
        if metrics.contains(.speed) {
            obdSpeedUpdatedAt = nil
            if externalSpeedUpdatedAt != nil { metrics.remove(.speed) }
        }
        let remaining = liveMetrics.subtracting(metrics)
        if remaining != liveMetrics { liveMetrics = remaining }
        if metrics.contains(.speed) { latestTelemetry.speedUpdatedAt = nil }
        if metrics.contains(.soc) {
            chargingEstimator.reset()
            invalidateEstimatedChargingPower()
        }
        if metrics.contains(.packVoltage) || metrics.contains(.packCurrent) {
            if liveMetrics.contains(.power) { liveMetrics.remove(.power) }
            latestTelemetry.powerKW = 0
            latestTelemetry.powerUpdatedAt = nil
            // SOC-derived charging power does not depend on a voltage/current read.
            if latestTelemetry.chargePowerSource != .socEstimate {
                latestTelemetry.chargePowerKW = 0
                latestTelemetry.isCharging = false
                latestTelemetry.chargePowerUpdatedAt = nil
                latestTelemetry.chargePowerSource = nil
            }
        }
        liveMetrics = TelemetryMetric.includingDerivedMetrics(liveMetrics)
        telemetryPublisher.send(latestTelemetry)
    }

    func expireExternalSpeed(at date: Date = .now) {
        guard let updatedAt = externalSpeedUpdatedAt,
            date.timeIntervalSince(updatedAt) > 15
        else { return }
        clearExternalSpeed()
    }

    private func resetTelemetryValidity() {
        if !liveMetrics.isEmpty { liveMetrics = [] }
        explicitChargingStatus = nil
        latestTelemetry.speedUpdatedAt = nil
        latestTelemetry.powerUpdatedAt = nil
        latestTelemetry.voltageUpdatedAt = nil
        latestTelemetry.currentUpdatedAt = nil
        latestTelemetry.vehicleRangeUpdatedAt = nil
        commandMetrics = [:]
        commandMisses = [:]
        externalSpeedUpdatedAt = nil
        obdSpeedUpdatedAt = nil
        latestTelemetry.isCharging = false
        latestTelemetry.chargePowerKW = 0
        latestTelemetry.chargePowerUpdatedAt = nil
        latestTelemetry.chargePowerSource = nil
        chargingTracker.reset()
        chargingSession = chargingTracker.state
        telemetryPublisher.send(latestTelemetry)
    }

    private func expireEstimatedChargingPower(at timestamp: Date) {
        guard latestTelemetry.chargePowerSource == .socEstimate,
            let socAt = latestTelemetry.socUpdatedAt,
            timestamp.timeIntervalSince(socAt) > 15
        else { return }
        chargingEstimator.reset()
        invalidateEstimatedChargingPower()
    }

    private func invalidateEstimatedChargingPower() {
        guard chargingEstimator.invalidate(snapshot: &latestTelemetry) else { return }
        chargingTracker.reset()
        chargingSession = chargingTracker.state
    }

    private func updateEstimatedChargingPower(soc: Double, snapshot: inout TelemetrySnapshot) {
        chargingEstimator.update(
            soc: soc,
            capacityKWh: usableBatteryCapacityKWh,
            timestamp: snapshot.timestamp,
            chargingPermitted: chargingPermitted(snapshot: snapshot),
            snapshot: &snapshot)
    }

    public func obdConnectionDidReceiveResponse(command: String, rawResponse: String) {
        // Handled via sendCommand completion or mock stream
        if isDemoMode, let mock = obdConnection as? MockOBDAdapter {
            let telemetry = mock.simulationEngine.telemetry
            publishTelemetry(telemetry)
            // Demo telemetry bypasses the polling path, so drive the live charging session
            // here as well instead of leaving it stuck at its idle state.
            updateChargingSession(telemetry)
        }
    }

    public func obdConnectionStateDidChange(_ state: BLEConnectionState) {
        self.connectionState = state
        if case .ready = state {
            initializeProfile()
        } else if case .disconnected = state {
            stopPolling()
            publishTelemetry(TelemetrySnapshot())
            chargingEstimator.reset()
            resetTelemetryValidity()
        } else if case .error = state {
            stopPolling()
            publishTelemetry(TelemetrySnapshot())
            chargingEstimator.reset()
            resetTelemetryValidity()
        }
    }

    private func initializeProfile(commandIndex: Int = 0, resumePolling: Bool = true) {
        if commandIndex == 0 {
            stopPolling()
            resetTelemetryValidity()
            isInitializing = true
            shouldPollAfterInitialization = resumePolling
            if case .ready(let name) = obdConnection.state {
                connectionState = .connecting(deviceName: name)
            }
        }
        let generation = pollingGeneration
        let commands = selectedProfile.initializationCommands
        guard commandIndex < commands.count else {
            isInitializing = false
            connectionState = obdConnection.state
            let shouldResume = shouldPollAfterInitialization
            shouldPollAfterInitialization = false
            if shouldResume { startPolling() }
            return
        }
        let command = commands[commandIndex]
        obdConnection.sendCommand(command) { [weak self] result in
            guard let self, self.isInitializing, generation == self.pollingGeneration else { return }
            let accepted: Bool
            if case .success(let raw) = result {
                let request = command.replacingOccurrences(of: " ", with: "").uppercased()
                if request.hasPrefix("10"), request.count == 4 {
                    // Bundled Zoe profiles enter a diagnostic session before reading PIDs.
                    let expected = "50" + request.suffix(2)
                    accepted = ISO15765Parser().assembleISOTPPayloads(raw).contains { $0.payload.hasPrefix(expected) }
                } else {
                    accepted = self.isSupportedResponse(command: command, rawResponse: raw)
                }
            } else {
                accepted = false
            }
            guard accepted else {
                self.stopPolling()
                self.obdConnection.disconnect()
                self.connectionState = .error("Adapter setup failed at \(command). Reconnect the scanner.")
                return
            }
            self.initializeProfile(commandIndex: commandIndex + 1, resumePolling: resumePolling)
        }
    }
}
