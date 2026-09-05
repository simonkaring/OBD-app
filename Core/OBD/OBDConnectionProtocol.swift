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
}

public struct TelemetrySnapshot: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var timestamp: Date = Date()
    public var speedKmH: Double = 0.0
    public var powerKW: Double = 0.0
    public var voltageV: Double = 0.0
    public var currentA: Double = 0.0
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
