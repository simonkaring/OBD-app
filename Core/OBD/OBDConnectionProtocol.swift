import Foundation

public enum TelemetryUpdate: Sendable {
    case speed(Double)                  // km/h
    case power(voltage: Double, current: Double, powerKW: Double) // V, A, kW (positive = draw, negative = regen)
    case packVoltage(Double)            // V, standalone (no matching current reading available)
    case packCurrent(Double)            // A, standalone (combined with the latest live pack voltage)
    case soc(Double)                    // State of Charge %
    case soh(Double)                    // State of Health %
    case batteryTemp(min: Double, max: Double, avg: Double) // °C
    case aux12V(Double)                 // Volts
    case motorStats(rpm: Double, torque: Double) // RPM, Nm
    case hvacPower(Double)              // kW
    /// `kwRate` is nil when the profile only knows *that* the car is charging (e.g. a
    /// status bit) but not at what rate — inventing a rate corrupts session kWh totals.
    case chargingStats(kwRate: Double?, acOrDc: String)
    case genericPid(mode: String, pid: String, rawValue: String)
    case fuelLevel(Double)              // %
    case throttlePosition(Double)       // %
    case engineLoad(Double)             // %
    case coolantTemp(Double)            // C
    case intakeAirTemp(Double)          // C
    case ambientAirTemp(Double)         // C
    case maf(Double)                    // grams/sec
    case manifoldPressure(Double)       // kPa
    case oilTemp(Double)                // C
    case timingAdvance(Double)          // degrees before TDC
    case barometricPressure(Double)     // kPa
    case vehicleRange(Double)           // km, reported by the vehicle
}

public enum ChargePowerSource: String, Codable, Sendable {
    case measured
    case socEstimate
}

public struct TelemetrySnapshot: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var timestamp: Date = Date()
    public var speedKmH: Double = 0.0
    public var speedUpdatedAt: Date?

    public var hasFreshSpeed: Bool {
        speedUpdatedAt.map { abs(timestamp.timeIntervalSince($0)) <= 15 } ?? false
    }
    public var powerKW: Double = 0.0
    public var powerUpdatedAt: Date?
    public var voltageV: Double = 0.0
    public var voltageUpdatedAt: Date?
    public var currentA: Double = 0.0
    public var currentUpdatedAt: Date?
    public var vehicleRangeKm: Double?
    public var vehicleRangeUpdatedAt: Date?
    /// Presentation-only value supplied by the active trip tracker.
    public var tripAverageConsumption: Double?

    public var hasFreshPower: Bool {
        powerUpdatedAt.map { (0...15).contains(timestamp.timeIntervalSince($0)) } ?? false
    }
    public var stateOfChargePct: Double = 0.0
    public var socUpdatedAt: Date?
    public var stateOfHealthPct: Double = 0.0
    public var batteryTempC: Double = 0.0
    public var batteryTempMinC: Double = 0.0
    public var batteryTempMaxC: Double = 0.0
    public var aux12VVolts: Double = 0.0
    public var motorRpm: Double = 0.0
    public var motorTorqueNm: Double = 0.0
    public var hvacPowerKW: Double = 0.0
    public var isCharging: Bool = false
    public var chargePowerKW: Double = 0.0
    public var chargePowerUpdatedAt: Date?
    public var chargePowerSource: ChargePowerSource?
    public var fuelLevelPct: Double = 0.0
    public var throttlePositionPct: Double = 0.0
    public var engineLoadPct: Double = 0.0
    public var coolantTempC: Double = 20.0
    public var intakeAirTempC: Double = 20.0
    public var ambientAirTempC: Double = 20.0
    public var mafGramsPerSec: Double = 0.0
    public var manifoldPressureKPa: Double = 100.0
    public var oilTempC: Double = 90.0
    public var timingAdvanceDeg: Double = 0.0
    public var barometricPressureKPa: Double = 100.0

    public init() {}
}

public protocol OBDConnectionDelegate: AnyObject {
    func obdConnectionDidReceiveResponse(command: String, rawResponse: String)
    func obdConnectionStateDidChange(_ state: BLEConnectionState)
}

public protocol OBDConnectionProtocol: AnyObject {
    var state: BLEConnectionState { get }
    var delegate: OBDConnectionDelegate? { get set }
    func connect(peripheralName: String?)
    func disconnect()
    func sendCommand(_ command: String, completion: ((Result<String, Error>) -> Void)?)
}

extension OBDConnectionProtocol {
    /// Reset restores automatic functional addressing for both 11- and 29-bit OBD.
    /// It also removes profile-specific receive filters, priority and raw CAN formatting.
    public static var diagnosticSetupCommands: [String] {
        ["AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT CAF 1", "AT SP 0"]
    }

    public static func diagnosticSetupCommands(for profileCommands: [String]) -> [String] {
        var commands = diagnosticSetupCommands
        // Retain the known bus protocol, but use the ELM's default functional header
        // and priority after reset (7DF for 11-bit, 18DB33F1 for 29-bit CAN).
        if let selectProtocol = profileCommands.last(where: {
            $0.replacingOccurrences(of: " ", with: "").uppercased().hasPrefix("ATSP")
        }) {
            commands[commands.count - 1] = selectProtocol
        }
        return commands
    }

    func sendSetupCommands(_ commands: [String], completion: @escaping (Bool) -> Void) {
        guard let command = commands.first else { completion(true); return }
        sendCommand(command) { [weak self] result in
            guard let self, case .success(let raw) = result else { completion(false); return }
            let request = command.replacingOccurrences(of: " ", with: "").uppercased()
            let lines = ISO15765Parser().cleanELMResponse(raw).uppercased().components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let accepted: Bool
            if request == "ATZ" {
                accepted = lines.contains { $0.contains("ELM") || $0.contains("OBD") || $0.contains("STN") }
            } else if request.hasPrefix("AT") {
                accepted = lines.contains("OK")
            } else {
                let expected = request.hasPrefix("10") ? "50" + request.suffix(2) : ""
                accepted = !expected.isEmpty && ISO15765Parser().assembleISOTPPayloads(raw).contains { $0.payload.hasPrefix(expected) }
            }
            guard accepted else { completion(false); return }
            self.sendSetupCommands(Array(commands.dropFirst()), completion: completion)
        }
    }
}
