import Foundation
import Combine
import SwiftUI

public final class VehicleDataManager: ObservableObject, OBDConnectionDelegate {
    @Published public private(set) var latestTelemetry = TelemetrySnapshot()
    @Published public private(set) var connectionState: BLEConnectionState = .disconnected
    @Published public private(set) var selectedProfile: VehicleProfile = MercedesEQA250Profile()
    @Published public private(set) var selectedProfileID: VehicleProfileID = .mercedesEQA250
    @Published public var isDemoMode: Bool = true

    public var obdConnection: OBDConnectionProtocol

    private var pollingTimer: AnyCancellable?
    private var pollingIndex = 0

    public init(connection: OBDConnectionProtocol? = nil) {
        if let conn = connection {
            self.obdConnection = conn
        } else {
            self.obdConnection = MockOBDAdapter()
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
            stopPolling()
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
        pollingTimer?.cancel()
        pollingTimer = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollNextCommand()
            }
    }

    public func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    private func pollNextCommand() {
        guard obdConnection.state.isConnected else { return }
        let cmds = selectedProfile.pollingCommands
        guard !cmds.isEmpty else { return }
        let cmd = cmds[pollingIndex % cmds.count]
        pollingIndex += 1

        obdConnection.sendCommand(cmd) { [weak self] result in
            guard let self = self else { return }
            if case .success(let raw) = result {
                if let update = self.selectedProfile.parseResponse(command: cmd, rawResponse: raw) {
                    self.applyUpdate(update)
                }
            }
        }
    }

    private func applyUpdate(_ update: TelemetryUpdate) {
        var snap = latestTelemetry
        snap.timestamp = Date()
        switch update {
        case .speed(let s): snap.speedKmH = s
        case .power(let v, let a, let kw):
            snap.voltageV = v
            snap.currentA = a
            snap.powerKW = kw
        case .soc(let soc): snap.stateOfChargePct = soc
        case .soh(let soh): snap.stateOfHealthPct = soh
        case .batteryTemp(_, _, let avg): snap.batteryTempC = avg
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
    }
}
