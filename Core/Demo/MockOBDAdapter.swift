import Foundation
import Combine

public final class MockOBDAdapter: ObservableObject, OBDConnectionProtocol {
    @Published public private(set) var state: BLEConnectionState = .demoMode
    public weak var delegate: OBDConnectionDelegate?

    public let simulationEngine = MockDrivingSimulation()
    private var cancellables = Set<AnyCancellable>()

    public init() {
        simulationEngine.start()
        simulationEngine.$telemetry
            .receive(on: DispatchQueue.main)
            .sink { [weak self] telemetry in
                self?.broadcastMockResponse(telemetry: telemetry)
            }
            .store(in: &cancellables)
    }

    public func connect(peripheralName: String? = nil) {
        state = .demoMode
        delegate?.obdConnectionStateDidChange(.demoMode)
    }

    public func disconnect() {
        simulationEngine.stop()
        state = .disconnected
        delegate?.obdConnectionStateDidChange(.disconnected)
    }

    public func sendCommand(_ command: String, completion: ((Result<String, Error>) -> Void)?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let mockHex: String
            switch command {
            case "AT Z", "AT Z\r": mockHex = "ELM327 v2.2\r\n>"
            case "AT E0", "AT E0\r": mockHex = "OK\r\n>"
            case "010D", "01 0D":
                let speedHex = String(format: "%02X", Int(self.simulationEngine.telemetry.speedKmH))
                mockHex = "41 0D \(speedHex)\r\n>"
            case "220101": // SOC
                let rawSoc = Int(self.simulationEngine.telemetry.stateOfChargePct * 2.0)
                mockHex = String(format: "62 01 01 %02X\r\n>", rawSoc)
            case "0104": // Engine Load
                let raw = Int(self.simulationEngine.telemetry.engineLoadPct * 255.0 / 100.0)
                mockHex = String(format: "41 04 %02X\r\n>", raw)
            case "0105": // Coolant Temp
                let raw = Int(self.simulationEngine.telemetry.coolantTempC + 40.0)
                mockHex = String(format: "41 05 %02X\r\n>", raw)
            case "010F": // Intake Air Temp
                let raw = Int(self.simulationEngine.telemetry.intakeAirTempC + 40.0)
                mockHex = String(format: "41 0F %02X\r\n>", raw)
            case "0111": // Throttle Position
                let raw = Int(self.simulationEngine.telemetry.throttlePositionPct * 255.0 / 100.0)
                mockHex = String(format: "41 11 %02X\r\n>", raw)
            case "012F": // Fuel Level
                let raw = Int(self.simulationEngine.telemetry.fuelLevelPct * 255.0 / 100.0)
                mockHex = String(format: "41 2F %02X\r\n>", raw)
            case "03", "03\r": // Scan DTCs
                if self.simulationEngine.scenario == .faultInjection || self.simulationEngine.injectedFaultCode != nil {
                    mockHex = "43 01 0A 80 00 00\r\n>" // P0A80
                } else {
                    mockHex = "43 00 00 00 00 00\r\n>"
                }
            default:
                mockHex = "OK\r\n>"
            }
            completion?(.success(mockHex))
        }
    }

    private func broadcastMockResponse(telemetry: TelemetrySnapshot) {
        let updateStr = String(format: "SOC: %.1f%% | Power: %.1f kW | Speed: %.1f km/h",
                               telemetry.stateOfChargePct,
                               telemetry.powerKW,
                               telemetry.speedKmH)
        delegate?.obdConnectionDidReceiveResponse(command: "MOCK", rawResponse: updateStr)
    }
}
