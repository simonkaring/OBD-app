import Foundation

/// Catalog of telemetry values that can be shown as a dashboard/CarPlay widget,
/// independent of which `VehicleProfile` (or `TelemetryUpdate` case) produced them.
public enum TelemetryMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case speed
    case power
    case soc
    case soh
    case batteryTemp
    case aux12V
    case motorRpm
    case motorTorque
    case fuelLevel
    case throttlePosition
    case engineLoad
    case coolantTemp
    case intakeAirTemp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .speed: return "Speed"
        case .power: return "Power"
        case .soc: return "State of Charge"
        case .soh: return "State of Health"
        case .batteryTemp: return "HV Battery Temp"
        case .aux12V: return "Auxiliary 12V"
        case .motorRpm: return "Motor RPM"
        case .motorTorque: return "Motor Torque"
        case .fuelLevel: return "Fuel Level"
        case .throttlePosition: return "Throttle Position"
        case .engineLoad: return "Engine Load"
        case .coolantTemp: return "Coolant Temp"
        case .intakeAirTemp: return "Intake Air Temp"
        }
    }

    public var unitSymbol: String {
        switch self {
        case .speed: return "km/h"
        case .power: return "kW"
        case .soc, .soh, .fuelLevel, .throttlePosition, .engineLoad: return "%"
        case .batteryTemp, .coolantTemp, .intakeAirTemp: return "°C"
        case .aux12V: return "V"
        case .motorRpm: return "RPM"
        case .motorTorque: return "Nm"
        }
    }

    public var sfSymbolName: String {
        switch self {
        case .speed: return "speedometer"
        case .power: return "gauge.with.needle.fill"
        case .soc, .fuelLevel: return "fuelpump.fill"
        case .soh: return "heart.fill"
        case .batteryTemp, .coolantTemp, .intakeAirTemp: return "thermometer.medium"
        case .aux12V: return "bolt.batteryblock"
        case .motorRpm: return "gauge.with.dots.needle.67percent"
        case .motorTorque: return "arrow.triangle.2.circlepath"
        case .throttlePosition: return "arrowtriangle.up.circle.fill"
        case .engineLoad: return "gauge.with.dots.needle.50percent"
        }
    }

    /// Normalization range used by dial/bar styles.
    public var defaultRange: ClosedRange<Double> {
        switch self {
        case .speed: return 0...200
        case .power: return -50...150
        case .soc, .soh, .fuelLevel, .throttlePosition, .engineLoad: return 0...100
        case .batteryTemp: return -20...60
        case .coolantTemp: return -20...120
        case .intakeAirTemp: return -20...60
        case .aux12V: return 9...15
        case .motorRpm: return 0...8000
        case .motorTorque: return -100...400
        }
    }

    public func value(in snapshot: TelemetrySnapshot) -> Double {
        switch self {
        case .speed: return snapshot.speedKmH
        case .power: return snapshot.powerKW
        case .soc: return snapshot.stateOfChargePct
        case .soh: return snapshot.stateOfHealthPct
        case .batteryTemp: return snapshot.batteryTempC
        case .aux12V: return snapshot.aux12VVolts
        case .motorRpm: return snapshot.motorRpm
        case .motorTorque: return snapshot.motorTorqueNm
        case .fuelLevel: return snapshot.fuelLevelPct
        case .throttlePosition: return snapshot.throttlePositionPct
        case .engineLoad: return snapshot.engineLoadPct
        case .coolantTemp: return snapshot.coolantTempC
        case .intakeAirTemp: return snapshot.intakeAirTempC
        }
    }
}
