import Foundation
import Combine
import SwiftUI

public final class VehicleDataManager: ObservableObject, OBDConnectionDelegate {
    public static let selectedVehicleIDDefaultsKey = "selectedVehicleID"

    @Published public private(set) var latestTelemetry = TelemetrySnapshot()
    @Published public private(set) var connectionState: BLEConnectionState = .disconnected
    @Published public private(set) var selectedProfile: VehicleProfile = MercedesEQA250Profile()
    @Published public private(set) var selectedProfileID: VehicleProfileID = .mercedesEQA250
    @Published public private(set) var selectedVehicle = VehicleCatalog.defaultModel
    @Published public private(set) var chargingSession = ChargingSessionState()
    @Published public var isDemoMode: Bool = false
    @Published public private(set) var isCalibrating: Bool = false
    @Published public private(set) var calibrationProgress: Double = 0.0
    @Published public private(set) var calibratedCommands: [String]? = nil
    @Published public private(set) var calibrationSummary: String? = nil
    @Published public private(set) var liveMetrics: Set<TelemetryMetric> = []

    public var obdConnection: OBDConnectionProtocol
    public let chargingTracker = ChargingSessionTracker()

    public var vehicleName: String { selectedVehicle.fullName }
    public var usableBatteryCapacityKWh: Double {
        selectedVehicle.batteryCapacityKWh > 0 ? selectedVehicle.batteryCapacityKWh : selectedProfile.batteryUsableCapacityKWh
    }
    public var estimatedFullRangeKm: Double {
        selectedVehicle.estimatedRangeKm ?? selectedProfile.estimatedFullRangeKm
    }

    public var hasChargePower: Bool {
        isDemoMode || latestTelemetry.chargePowerUpdatedAt != nil
    }

    private var isPolling = false
    private var isInitializing = false
    private var shouldPollAfterInitialization = false
    private var pollingIndex = 0
    private var pollingGeneration = 0
    private var socHistory: [(timestamp: Date, value: Double)] = []
    private var commandMetrics: [String: Set<TelemetryMetric>] = [:]
    private var commandMisses: [String: Int] = [:]
    private var externalSpeedUpdatedAt: Date?
    private let persistenceDefaults: UserDefaults?

    public var supportedMetrics: Set<TelemetryMetric> {
        var metrics = selectedProfile.supportedMetrics
        if selectedProfileID == .mercedesEQA250 { metrics.insert(.speed) }
        return metrics
    }

    public init(connection: OBDConnectionProtocol? = nil, userDefaults: UserDefaults? = nil) {
        if let userDefaults {
            self.persistenceDefaults = userDefaults
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                    ProcessInfo.processInfo.processName.localizedCaseInsensitiveContains("xctest") {
            self.persistenceDefaults = nil
        } else {
            self.persistenceDefaults = .standard
        }

        if let selectedVehicleID = persistenceDefaults?.string(forKey: Self.selectedVehicleIDDefaultsKey),
           let restoredVehicle = VehicleCatalog.allModels.first(where: { $0.id == selectedVehicleID }) {
            self.selectedVehicle = restoredVehicle
            self.selectedProfileID = restoredVehicle.profileID
            self.selectedProfile = restoredVehicle.profileID.makeProfile()
        }

        if let conn = connection {
            self.obdConnection = conn
        } else {
            self.obdConnection = BluetoothManager()
        }
        self.obdConnection.delegate = self
    }

    public func toggleDemoMode(_ enabled: Bool) {
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
            latestTelemetry = TelemetrySnapshot()
            resetTelemetryValidity()
            stopPolling()
        }
    }

    public func clearDemoData() {
        latestTelemetry = TelemetrySnapshot()
        socHistory.removeAll()
        if let mock = obdConnection as? MockOBDAdapter {
            mock.simulationEngine.scenario = .cityDriving
            mock.simulationEngine.injectedFaultCode = nil
            mock.simulationEngine.userSpeedOverride = nil
            mock.simulationEngine.userThrottleOverride = nil
            mock.simulationEngine.userRegenOverride = nil
        }
    }

    public func selectProfile(_ id: VehicleProfileID) {
        let wasPolling = isPolling
        stopPolling()
        selectedProfileID = id
        selectedProfile = id.makeProfile()
        calibratedCommands = nil
        calibrationSummary = nil
        pollingIndex = 0
        socHistory.removeAll()
        resetTelemetryValidity()
        if !isDemoMode, obdConnection.state.isConnected {
            initializeProfile(resumePolling: wasPolling)
        }
    }

    public func selectVehicle(_ vehicle: VehicleModelEntry) {
        selectedVehicle = vehicle
        selectProfile(vehicle.profileID)
        persistenceDefaults?.set(vehicle.id, forKey: Self.selectedVehicleIDDefaultsKey)
    }

    public func startCalibration() {
        guard !isCalibrating, !isInitializing else { return }
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
                    let applied = updates.reduce(false) { self.applyUpdate($1, timestamp: .now, sourceCommand: cmd) || $0 }
                    if !applied {
                        self.recordMiss(for: cmd)
                    }
                }
                self.calibrationProgress = Double(index + 1) / Double(total)
            }

            let respondingReadCount = verifiedCommands.filter { !$0.uppercased().hasPrefix("AT") }.count
            if respondingReadCount > 0 {
                // Keep EQA voltage and the undecoded capture DID polling after a miss.
                self.calibratedCommands = self.selectedProfileID == .mercedesEQA250 ? nil : verifiedCommands
                let totalReadCount = commandsToTest.filter { !$0.uppercased().hasPrefix("AT") }.count
                self.calibrationSummary = "\(respondingReadCount) of \(totalReadCount) reads responded"
            } else {
                self.calibratedCommands = nil
                self.calibrationSummary = "No reads responded"
            }
            self.pollingIndex = 0
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
        await withCheckedContinuation { continuation in
            self.obdConnection.sendCommand(command) { result in
                switch result {
                case .success(let raw):
                    continuation.resume(returning: raw)
                case .failure:
                    continuation.resume(returning: "")
                }
            }
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
        guard !isDemoMode, !isPolling else { return }
        if isInitializing {
            shouldPollAfterInitialization = true
            return
        }
        isPolling = true
        pollingGeneration += 1
        pollNextCommand(generation: pollingGeneration)
    }

    public func stopPolling() {
        isPolling = false
        isInitializing = false
        shouldPollAfterInitialization = false
        isCalibrating = false
        pollingGeneration += 1
        socHistory.removeAll()
        invalidateEstimatedChargingPower()
    }

    private func pollNextCommand(generation: Int) {
        guard isPolling, generation == pollingGeneration else { return }
        guard obdConnection.state.isConnected else {
            scheduleNextPoll(generation: generation)
            return
        }
        let cmds = calibratedCommands ?? selectedProfile.pollingCommands
        guard !cmds.isEmpty else {
            scheduleNextPoll(generation: generation)
            return
        }
        let cmd = cmds[pollingIndex % cmds.count]
        pollingIndex += 1

        obdConnection.sendCommand(cmd) { [weak self] result in
            guard let self = self, self.isPolling, generation == self.pollingGeneration else { return }
            if cmd.uppercased().hasPrefix("AT") {
                guard case .success(let raw) = result,
                      self.isSupportedResponse(command: cmd, rawResponse: raw) else {
                    self.stopPolling()
                    self.resetTelemetryValidity()
                    self.obdConnection.disconnect()
                    self.connectionState = .error("Adapter routing failed at \(cmd). Reconnect the scanner.")
                    return
                }
                self.scheduleNextPoll(generation: generation)
                return
            }
            if case .success(let raw) = result {
                let updates = self.selectedProfile.parseResponses(command: cmd, rawResponse: raw)
                let applied = updates.reduce(false) { self.applyUpdate($1, timestamp: .now, sourceCommand: cmd) || $0 }
                if !applied {
                    self.recordMiss(for: cmd)
                }
            } else {
                self.recordMiss(for: cmd)
            }
            self.expireExternalSpeed()
            self.expireEstimatedChargingPower(at: .now)
            self.scheduleNextPoll(generation: generation)
        }
    }

    private func scheduleNextPoll(generation: Int, delay: TimeInterval = 0.05) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pollNextCommand(generation: generation)
        }
    }

    func applyUpdate(_ update: TelemetryUpdate) {
        applyUpdate(update, timestamp: .now, sourceCommand: nil)
    }

    func applyUpdate(_ update: TelemetryUpdate, timestamp: Date) {
        applyUpdate(update, timestamp: timestamp, sourceCommand: nil)
    }

    func applyExternalSpeed(_ speedKmH: Double, timestamp: Date = .now) {
        externalSpeedUpdatedAt = timestamp
        applyUpdate(.speed(speedKmH), timestamp: timestamp, sourceCommand: nil)
    }

    public func clearExternalSpeed() {
        externalSpeedUpdatedAt = nil
        latestTelemetry.speedKmH = 0
        liveMetrics.remove(.speed)
    }

    /// Physically plausible bounds per decoded quantity. Several vehicle profiles carry
    /// unverified community scaling factors; rejecting out-of-range values here means a
    /// wrong decode shows up as *missing* data on the dashboard rather than as garbage,
    /// and protects every profile at once instead of clamping in each decoder.
    static func isPlausible(_ update: TelemetryUpdate) -> Bool {
        func ok(_ value: Double, _ range: ClosedRange<Double>) -> Bool {
            value.isFinite && range.contains(value)
        }

        switch update {
        case .speed(let v):                     return ok(v, 0...400)
        case .power(let volts, let amps, let kw):
            return ok(volts, 0...1_000) && ok(amps, -1_500...1_500) && ok(kw, -1_000...1_000)
        case .packVoltage(let v):               return ok(v, 0...1_000)
        case .packCurrent(let v):               return ok(v, -1_500...1_500)
        case .soc(let v):                       return ok(v, 0...100)
        case .soh(let v):                       return ok(v, 0...100)
        case .batteryTemp(let lo, let hi, let avg):
            return ok(lo, -50...100) && ok(hi, -50...100) && ok(avg, -50...100)
        case .aux12V(let v):                    return ok(v, 0...36)
        case .motorStats(let rpm, let torque):  return ok(rpm, -30_000...30_000) && ok(torque, -5_000...5_000)
        case .hvacPower(let v):                 return ok(v, -50...50)
        case .chargingStats(let kw, _):         return kw.map { ok($0, 0...600) } ?? true
        case .fuelLevel(let v):                 return ok(v, 0...100)
        case .throttlePosition(let v):          return ok(v, 0...100)
        case .engineLoad(let v):                return ok(v, 0...100)
        case .coolantTemp(let v):               return ok(v, -50...250)
        case .intakeAirTemp(let v):             return ok(v, -50...200)
        case .ambientAirTemp(let v):            return ok(v, -60...80)
        case .maf(let v):                       return ok(v, 0...700)
        case .manifoldPressure(let v):          return ok(v, 0...500)
        case .oilTemp(let v):                   return ok(v, -50...250)
        case .timingAdvance(let v):             return ok(v, -70...70)
        case .barometricPressure(let v):        return ok(v, 0...300)
        case .genericPid:                       return true
        }
    }

    @discardableResult
    private func applyUpdate(_ update: TelemetryUpdate, timestamp: Date, sourceCommand: String?) -> Bool {
        guard Self.isPlausible(update) else {
            return false
        }
        var snap = latestTelemetry
        snap.timestamp = timestamp
        if let socAt = snap.socUpdatedAt, timestamp.timeIntervalSince(socAt) > 15 {
            clearEstimatedChargingPower(snapshot: &snap)
            socHistory.removeAll()
        }
        var updatedMetrics = metrics(for: update)
        switch update {
        case .speed(let s):
            snap.speedKmH = s
            if s > 1.0 {
                clearEstimatedChargingPower(snapshot: &snap)
                socHistory.removeAll()
                // If moving, we cannot be plugged in and charging
                snap.isCharging = false
                snap.chargePowerKW = 0.0
            }

        case .power(let v, let a, let kw):
            clearEstimatedChargingPower(snapshot: &snap)
            snap.voltageV = v
            snap.currentA = a
            snap.powerKW = kw
            // Negative pack current = energy into the battery. Only treat it as
            // charging (not regen) when parked, since regen only occurs while moving.
            if a < -1.0 && snap.speedKmH < 1.0 {
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
            updatePackPower(snapshot: &snap, updatedMetrics: &updatedMetrics)

        case .packCurrent(let current):
            snap.currentA = current
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
        case .genericPid: break
        }
        liveMetrics.formUnion(updatedMetrics)
        if let sourceCommand {
            commandMetrics[sourceCommand, default: []].formUnion(updatedMetrics)
            commandMisses[sourceCommand] = 0
        }
        latestTelemetry = snap

        // Update live charging session tracker
        let isStationary = snap.speedKmH < 1.0
        let currentPower = snap.isCharging ? (snap.chargePowerKW > 0 ? snap.chargePowerKW : abs(snap.powerKW)) : (snap.currentA < -1.0 && isStationary ? abs(snap.powerKW) : nil)
        self.chargingSession = chargingTracker.update(
            soc: snap.stateOfChargePct,
            packVoltage: snap.voltageV,
            // A genuine 0 A reading (idle pack) is data, not "no data" — key off whether
            // pack current has ever decoded rather than off a 0.0 sentinel.
            packCurrent: liveMetrics.contains(.packCurrent) ? snap.currentA : nil,
            powerKW: currentPower,
            vehicleBatteryCapacityKWh: usableBatteryCapacityKWh,
            isStationary: isStationary
        )
        return true
    }

    private func updatePackPower(snapshot: inout TelemetrySnapshot, updatedMetrics: inout Set<TelemetryMetric>) {
        let available = liveMetrics.union(updatedMetrics)
        guard available.contains(.packVoltage), available.contains(.packCurrent) else { return }
        clearEstimatedChargingPower(snapshot: &snapshot)
        snapshot.powerKW = (snapshot.voltageV * snapshot.currentA) / 1000.0
        updatedMetrics.insert(.power)
        if snapshot.currentA < -1.0 && snapshot.speedKmH < 1.0 {
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
        case .hvacPower, .chargingStats, .genericPid: []
        }
    }

    private func recordMiss(for command: String) {
        guard let metrics = commandMetrics[command] else { return }
        commandMisses[command, default: 0] += 1
        guard commandMisses[command, default: 0] >= 3 else { return }
        liveMetrics.subtract(metrics)
        if metrics.contains(.soc) {
            socHistory.removeAll()
            invalidateEstimatedChargingPower()
        }
        if metrics.contains(.packVoltage) || metrics.contains(.packCurrent) {
            liveMetrics.remove(.power)
            latestTelemetry.powerKW = 0
            // SOC-derived charging power does not depend on a voltage/current read.
            if latestTelemetry.chargePowerSource != .socEstimate {
                latestTelemetry.chargePowerKW = 0
                latestTelemetry.isCharging = false
                latestTelemetry.chargePowerUpdatedAt = nil
                latestTelemetry.chargePowerSource = nil
            }
        }
    }

    private func expireExternalSpeed() {
        guard let updatedAt = externalSpeedUpdatedAt,
              Date.now.timeIntervalSince(updatedAt) > 15 else { return }
        clearExternalSpeed()
    }

    private func resetTelemetryValidity() {
        liveMetrics = []
        commandMetrics = [:]
        commandMisses = [:]
        externalSpeedUpdatedAt = nil
        latestTelemetry.isCharging = false
        latestTelemetry.chargePowerKW = 0
        latestTelemetry.chargePowerUpdatedAt = nil
        latestTelemetry.chargePowerSource = nil
        chargingTracker.reset()
        chargingSession = chargingTracker.state
    }

    private func clearEstimatedChargingPower(snapshot: inout TelemetrySnapshot) {
        guard snapshot.chargePowerSource == .socEstimate else { return }
        snapshot.isCharging = false
        snapshot.chargePowerKW = 0
        snapshot.chargePowerUpdatedAt = nil
        snapshot.chargePowerSource = nil
    }

    private func expireEstimatedChargingPower(at timestamp: Date) {
        guard latestTelemetry.chargePowerSource == .socEstimate,
              let socAt = latestTelemetry.socUpdatedAt,
              timestamp.timeIntervalSince(socAt) > 15 else { return }
        socHistory.removeAll()
        invalidateEstimatedChargingPower()
    }

    private func invalidateEstimatedChargingPower() {
        guard latestTelemetry.chargePowerSource == .socEstimate else { return }
        clearEstimatedChargingPower(snapshot: &latestTelemetry)
        chargingTracker.reset()
        chargingSession = chargingTracker.state
    }

    private func updateEstimatedChargingPower(soc: Double, snapshot: inout TelemetrySnapshot) {
        // A profile that reports pack current has better information than an
        // SOC slope. Keep its reading until it is stale.
        if snapshot.chargePowerSource == .measured,
           let directPowerAt = snapshot.chargePowerUpdatedAt,
           snapshot.timestamp.timeIntervalSince(directPowerAt) < 10 {
            return
        }

        guard snapshot.speedKmH < 1.0 else {
            socHistory.removeAll()
            clearEstimatedChargingPower(snapshot: &snapshot)
            return
        }

        socHistory.append((snapshot.timestamp, soc))
        let cutoff = snapshot.timestamp.addingTimeInterval(-90)
        socHistory.removeAll { $0.timestamp < cutoff }

        guard let oldest = socHistory.first else { return }
        let duration = snapshot.timestamp.timeIntervalSince(oldest.timestamp)
        let delta = soc - oldest.value
        guard duration >= 30 else { return }
        guard delta > 0 else {
            clearEstimatedChargingPower(snapshot: &snapshot)
            return
        }

        let kw = (delta / 100 * usableBatteryCapacityKWh) / (duration / 3_600)
        guard (0.5...200).contains(kw) else {
            clearEstimatedChargingPower(snapshot: &snapshot)
            return
        }
        snapshot.isCharging = true
        snapshot.chargePowerKW = kw
        snapshot.chargePowerUpdatedAt = snapshot.timestamp
        snapshot.chargePowerSource = .socEstimate
    }

    public func obdConnectionDidReceiveResponse(command: String, rawResponse: String) {
        // Handled via sendCommand completion or mock stream
        if isDemoMode, let mock = obdConnection as? MockOBDAdapter {
            self.latestTelemetry = mock.simulationEngine.telemetry
        }
    }

    public func obdConnectionStateDidChange(_ state: BLEConnectionState) {
        self.connectionState = state
        if case .ready = state {
            initializeProfile()
        } else if case .disconnected = state {
            stopPolling()
            latestTelemetry = TelemetrySnapshot()
            socHistory.removeAll()
            resetTelemetryValidity()
        } else if case .error = state {
            stopPolling()
            latestTelemetry = TelemetrySnapshot()
            socHistory.removeAll()
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
