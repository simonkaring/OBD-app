import Foundation

public enum TelemetryUpdate: Sendable {
    case speed(Double)                  // km/h
    case power(voltage: Double, current: Double, powerKW: Double) // V, A, kW (positive = draw, negative = regen)
    case soc(Double)                    // State of Charge %
    case soh(Double)                    // State of Health %
    case batteryTemp(min: Double, max: Double, avg: Double) // °C
    case aux12V(Double)                 // Volts
    case motorStats(rpm: Double, torque: Double) // RPM, Nm
    case hvacPower(Double)              // kW
    case chargingStats(kwRate: Double, acOrDc: String)
    case genericPid(mode: String, pid: String, rawValue: String)
}

public struct TelemetrySnapshot: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var timestamp: Date = Date()
    public var speedKmH: Double = 0.0
    public var powerKW: Double = 0.0
    public var voltageV: Double = 0.0
    public var currentA: Double = 0.0
    public var stateOfChargePct: Double = 0.0
    public var stateOfHealthPct: Double = 98.5
    public var batteryTempC: Double = 25.0
    public var aux12VVolts: Double = 12.6
    public var motorRpm: Double = 0.0
    public var motorTorqueNm: Double = 0.0
    public var hvacPowerKW: Double = 0.0
    public var isCharging: Bool = false
    public var chargePowerKW: Double = 0.0

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
