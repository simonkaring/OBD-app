import Foundation
import Combine
import SwiftUI

public final class VehicleDataManager: ObservableObject, OBDConnectionDelegate {
    @Published public private(set) var latestTelemetry = TelemetrySnapshot()
    @Published public private(set) var connectionState: BLEConnectionState = .disconnected
    @Published public private(set) var selectedProfile: VehicleProfile = MercedesEQA250Profile()
    @Published public private(set) var selectedProfileID: VehicleProfileID = .mercedesEQA250
    @Published public var isDemoMode: Bool = false

    public var obdConnection: OBDConnectionProtocol

    private var isPolling = false
    private var pollingIndex = 0
    private var pollingGeneration = 0

    public init(connection: OBDConnectionProtocol? = nil) {
        if let conn = connection {
            self.obdConnection = conn
        } else {
            self.obdConnection = BluetoothManager()
        }
        self.obdConnection.delegate = self
        if isDemoMode {
            startPolling()
        }
    }

    public func toggleDemoMode(_ enabled: Bool) {
        isDemoMode = enabled
        if enabled {
            let mock = MockOBDAdapter()
            self.obdConnection = mock
            self.obdConnection.delegate = self
            connectionState = .demoMode
            startPolling()
        } else {
            let ble = BluetoothManager()
            self.obdConnection = ble
            self.obdConnection.delegate = self
            connectionState = .disconnected
            latestTelemetry = TelemetrySnapshot()
            stopPolling()
        }
    }

    public func clearDemoData() {
        latestTelemetry = TelemetrySnapshot()
        if let mock = obdConnection as? MockOBDAdapter {
            mock.simulationEngine.scenario = .cityDriving
            mock.simulationEngine.injectedFaultCode = nil
            mock.simulationEngine.userSpeedOverride = nil
            mock.simulationEngine.userThrottleOverride = nil
            mock.simulationEngine.userRegenOverride = nil
        }
    }

    public func selectProfile(_ id: VehicleProfileID) {
        selectedProfileID = id
        selectedProfile = id.makeProfile()
        pollingIndex = 0
        for cmd in selectedProfile.initializationCommands {
            obdConnection.sendCommand(cmd, completion: nil)
        }
    }

    public func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        pollingGeneration += 1
        pollNextCommand(generation: pollingGeneration)
    }

    public func stopPolling() {
        isPolling = false
        pollingGeneration += 1
    }

    private func pollNextCommand(generation: Int) {
        guard isPolling, generation == pollingGeneration else { return }
        guard obdConnection.state.isConnected else {
            scheduleNextPoll(generation: generation)
            return
        }
        let cmds = selectedProfile.pollingCommands
        guard !cmds.isEmpty else {
            scheduleNextPoll(generation: generation)
            return
        }
        let cmd = cmds[pollingIndex % cmds.count]
        pollingIndex += 1

        obdConnection.sendCommand(cmd) { [weak self] result in
            guard let self = self else { return }
            if case .success(let raw) = result {
                if let update = self.selectedProfile.parseResponse(command: cmd, rawResponse: raw) {
                    self.applyUpdate(update)
                }
            }
            self.scheduleNextPoll(generation: generation)
        }
    }

    private func scheduleNextPoll(generation: Int, delay: TimeInterval = 0.05) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pollNextCommand(generation: generation)
        }
    }

    func applyUpdate(_ update: TelemetryUpdate) {
        var snap = latestTelemetry
        snap.timestamp = Date()
        switch update {
        case .speed(let s): snap.speedKmH = s
        case .power(let v, let a, let kw):
            snap.voltageV = v
            snap.currentA = a
            snap.powerKW = kw
            // Negative pack current = energy into the battery. Only treat it as
            // charging (not regen) when parked, since regen only occurs while moving.
            if a < -1.0 && snap.speedKmH < 1.0 {
                snap.isCharging = true
                snap.chargePowerKW = abs(kw)
            } else if a >= -1.0 {
                snap.isCharging = false
                snap.chargePowerKW = 0.0
            }
        case .soc(let soc): snap.stateOfChargePct = soc
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
            snap.isCharging = kw > 0.5
            snap.chargePowerKW = kw
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
        latestTelemetry = snap
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
            for cmd in selectedProfile.initializationCommands {
                obdConnection.sendCommand(cmd, completion: nil)
            }
            startPolling()
        } else if case .disconnected = state {
            stopPolling()
            latestTelemetry = TelemetrySnapshot()
        }
    }
}
