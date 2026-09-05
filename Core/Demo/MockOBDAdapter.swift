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
            case "010C", "01 0C":
                let rawRpm = Int(self.simulationEngine.telemetry.motorRpm * 4.0)
                let byteA = (rawRpm >> 8) & 0xFF
                let byteB = rawRpm & 0xFF
                mockHex = String(format: "41 0C %02X %02X\r\n>", byteA, byteB)
            case "0142", "01 42":
                let rawVolts = Int(self.simulationEngine.telemetry.aux12VVolts * 1000.0)
                let byteA = (rawVolts >> 8) & 0xFF
                let byteB = rawVolts & 0xFF
                mockHex = String(format: "41 42 %02X %02X\r\n>", byteA, byteB)
            case "22010A", "22 01 0A": // Mercedes EQA pack voltage
                let rawV = Int((self.simulationEngine.telemetry.voltageV > 0 ? self.simulationEngine.telemetry.voltageV : 398.0) * 10.0)
                let byteA = (rawV >> 8) & 0xFF
                let byteB = rawV & 0xFF
                mockHex = String(format: "62 01 0A %02X %02X\r\n>", byteA, byteB)
            case "220210", "22 02 10": // Mercedes EQA customer SOC
                let grossSoC = 29.8 + (self.simulationEngine.telemetry.stateOfChargePct / 100.0) * (96.0 - 29.8)
                let raw = UInt32(grossSoC * 250.0)
                let b1 = (raw >> 24) & 0xFF
                let b2 = (raw >> 16) & 0xFF
                let b3 = (raw >> 8) & 0xFF
                let b4 = raw & 0xFF
                mockHex = String(format: "62 02 10 04 %02X %02X %02X %02X\r\n>", b1, b2, b3, b4)
            case "22010B", "22 01 0B": // Mercedes EQA current
                let rawCurrent = Int16(self.simulationEngine.telemetry.currentA * 10.0)
                let bA = UInt8(bitPattern: Int8((rawCurrent >> 8) & 0xFF))
                let bB = UInt8(bitPattern: Int8(rawCurrent & 0xFF))
                mockHex = String(format: "62 01 0B %02X %02X\r\n>", bA, bB)
            case "22010C", "22 01 0C": // Mercedes EQA battery temp
                let rawTemp = UInt8(max(0, min(255, Int(self.simulationEngine.telemetry.batteryTempC + 40.0))))
                mockHex = String(format: "62 01 0C %02X\r\n>", rawTemp)
            case "220101": // Hyundai SOC / Power
                let rawSoc = Int(self.simulationEngine.telemetry.stateOfChargePct * 2.0)
                mockHex = String(format: "62 01 01 00 00 00 00 00 00 00 00 00 00 00 0F A0 %02X\r\n>", rawSoc)
            case "220105": // Hyundai SOC
                let rawSoc = Int(self.simulationEngine.telemetry.stateOfChargePct * 2.0)
                var bytes = [UInt8](repeating: 0, count: 35)
                bytes[32] = UInt8(max(0, min(200, rawSoc)))
                let hexStr = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                mockHex = "62 01 05 \(hexStr)\r\n>"
            case "03221E3D55555555": // VW MEB HV current (DID 0x1E3D)
                let current = self.simulationEngine.telemetry.currentA
                let rawVal = Int(max(0, 150_000.0 - current * 100.0))
                let bA = (rawVal >> 24) & 0xFF
                let bB = (rawVal >> 16) & 0xFF
                let bC = (rawVal >> 8) & 0xFF
                let bD = rawVal & 0xFF
                mockHex = String(format: "62 1E 3D %02X %02X %02X %02X\r\n>", bA, bB, bC, bD)
            case "03221E3B55555555": // VW MEB HV voltage (DID 0x1E3B)
                let rawV = Int((self.simulationEngine.telemetry.voltageV > 0 ? self.simulationEngine.telemetry.voltageV : 398.0) * 4.0)
                let bA = (rawV >> 8) & 0xFF
                let bB = rawV & 0xFF
                mockHex = String(format: "62 1E 3B %02X %02X\r\n>", bA, bB)
            case "0322028C55555555": // VW MEB display SOC (DID 0x028C)
                let soc = self.simulationEngine.telemetry.stateOfChargePct
                let rawSoc = Int(((soc + 7.16) * 2.5 / 1.12).rounded())
                mockHex = String(format: "62 02 8C %02X\r\n>", max(0, min(255, rawSoc)))
            case "0322744855555555": // VW MEB charging status (DID 0x7448)
                let statusByte: UInt8 = self.simulationEngine.telemetry.isCharging ? 0x04 : 0x00
                mockHex = String(format: "62 74 48 %02X\r\n>", statusByte)
            case "0104", "01 04": // Engine Load
                let raw = Int(self.simulationEngine.telemetry.engineLoadPct * 255.0 / 100.0)
                mockHex = String(format: "41 04 %02X\r\n>", raw)
            case "0105", "01 05": // Coolant Temp
                let raw = Int(self.simulationEngine.telemetry.coolantTempC + 40.0)
                mockHex = String(format: "41 05 %02X\r\n>", raw)
            case "010F", "01 0F": // Intake Air Temp
                let raw = Int(self.simulationEngine.telemetry.intakeAirTempC + 40.0)
                mockHex = String(format: "41 0F %02X\r\n>", raw)
            case "0111", "01 11": // Throttle Position
                let raw = Int(self.simulationEngine.telemetry.throttlePositionPct * 255.0 / 100.0)
                mockHex = String(format: "41 11 %02X\r\n>", raw)
            case "012F", "01 2F": // Fuel Level
                let raw = Int(self.simulationEngine.telemetry.fuelLevelPct * 255.0 / 100.0)
                mockHex = String(format: "41 2F %02X\r\n>", raw)
            case "015B", "01 5B": // EV SOC
                let raw = Int(self.simulationEngine.telemetry.stateOfChargePct * 255.0 / 100.0)
                mockHex = String(format: "41 5B %02X\r\n>", raw)
            case "0146", "01 46": // Ambient Air Temp
                let raw = Int(self.simulationEngine.telemetry.ambientAirTempC + 40.0)
                mockHex = String(format: "41 46 %02X\r\n>", raw)
            case "0110", "01 10": // MAF
                let raw = Int(self.simulationEngine.telemetry.mafGramsPerSec * 100.0)
                let bA = (raw >> 8) & 0xFF
                let bB = raw & 0xFF
                mockHex = String(format: "41 10 %02X %02X\r\n>", bA, bB)
            case "010B", "01 0B": // Manifold Pressure
                let raw = Int(self.simulationEngine.telemetry.manifoldPressureKPa)
                mockHex = String(format: "41 0B %02X\r\n>", raw)
            case "015C", "01 5C": // Oil Temp
                let raw = Int(self.simulationEngine.telemetry.oilTempC + 40.0)
                mockHex = String(format: "41 5C %02X\r\n>", raw)
            case "010E", "01 0E": // Timing Advance
                let raw = Int((self.simulationEngine.telemetry.timingAdvanceDeg + 64.0) * 2.0)
                mockHex = String(format: "41 0E %02X\r\n>", raw)
            case "0133", "01 33": // Barometric Pressure
                let raw = Int(self.simulationEngine.telemetry.barometricPressureKPa)
                mockHex = String(format: "41 33 %02X\r\n>", raw)
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
