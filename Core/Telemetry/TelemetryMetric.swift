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
    case packVoltage
    case packCurrent
    case batteryTempMin
    case batteryTempMax
    case ambientAirTemp
    case maf
    case manifoldPressure
    case oilTemp
    case timingAdvance
    case barometricPressure
    case instantEfficiency

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
        case .packVoltage: return "Pack Voltage"
        case .packCurrent: return "Pack Current"
        case .batteryTempMin: return "Battery Temp Min"
        case .batteryTempMax: return "Battery Temp Max"
        case .ambientAirTemp: return "Ambient Air Temp"
        case .maf: return "Mass Air Flow"
        case .manifoldPressure: return "Manifold Pressure"
        case .oilTemp: return "Oil Temp"
        case .timingAdvance: return "Timing Advance"
        case .barometricPressure: return "Barometric Pressure"
        case .instantEfficiency: return "Instant Efficiency"
        }
    }

    public var unitSymbol: String {
        switch self {
        case .speed: return "km/h"
        case .power: return "kW"
        case .soc, .soh, .fuelLevel, .throttlePosition, .engineLoad: return "%"
        case .batteryTemp, .coolantTemp, .intakeAirTemp, .batteryTempMin, .batteryTempMax, .ambientAirTemp, .oilTemp: return "°C"
        case .aux12V, .packVoltage: return "V"
        case .motorRpm: return "RPM"
        case .motorTorque: return "Nm"
        case .packCurrent: return "A"
        case .maf: return "g/s"
        case .manifoldPressure, .barometricPressure: return "kPa"
        case .timingAdvance: return "°"
        case .instantEfficiency: return "kWh/100km"
        }
    }

    public var sfSymbolName: String {
        switch self {
        case .speed: return "speedometer"
        case .power: return "gauge.with.needle.fill"
        case .soc, .fuelLevel: return "fuelpump.fill"
        case .soh: return "heart.fill"
        case .batteryTemp, .coolantTemp, .intakeAirTemp, .batteryTempMin, .batteryTempMax, .ambientAirTemp, .oilTemp: return "thermometer.medium"
        case .aux12V: return "bolt.batteryblock"
        case .motorRpm: return "gauge.with.dots.needle.67percent"
        case .motorTorque: return "arrow.triangle.2.circlepath"
        case .throttlePosition: return "arrowtriangle.up.circle.fill"
        case .engineLoad: return "gauge.with.dots.needle.50percent"
        case .packVoltage: return "bolt.fill"
        case .packCurrent: return "bolt.horizontal.fill"
        case .maf: return "wind"
        case .manifoldPressure, .barometricPressure: return "gauge.low"
        case .timingAdvance: return "timer"
        case .instantEfficiency: return "leaf.fill"
        }
    }

    /// Normalization range used by dial/bar styles.
    public var defaultRange: ClosedRange<Double> {
        switch self {
        case .speed: return 0...200
        case .power: return -50...150
        case .soc, .soh, .fuelLevel, .throttlePosition, .engineLoad: return 0...100
        case .batteryTemp, .batteryTempMin, .batteryTempMax: return -20...60
        case .coolantTemp: return -20...120
        case .intakeAirTemp: return -20...60
        case .aux12V: return 9...15
        case .motorRpm: return 0...8000
        case .motorTorque: return -100...400
        case .packVoltage: return 250...450
        case .packCurrent: return -300...300
        case .ambientAirTemp: return -20...50
        case .maf: return 0...200
        case .manifoldPressure, .barometricPressure: return 20...120
        case .oilTemp: return -20...150
        case .timingAdvance: return -30...60
        case .instantEfficiency: return 0...40
        }
    }

    /// Decimal places to render at in the numeric tile — a bare `%.0f` rounds
    /// small-magnitude values like 12.6V to an indistinguishable "13".
    public var decimalPlaces: Int {
        switch self {
        case .packVoltage, .aux12V, .instantEfficiency: return 1
        case .power, .packCurrent: return 1
        default: return 0
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
        case .packVoltage: return snapshot.voltageV
        case .packCurrent: return snapshot.currentA
        case .batteryTempMin: return snapshot.batteryTempMinC
        case .batteryTempMax: return snapshot.batteryTempMaxC
        case .ambientAirTemp: return snapshot.ambientAirTempC
        case .maf: return snapshot.mafGramsPerSec
        case .manifoldPressure: return snapshot.manifoldPressureKPa
        case .oilTemp: return snapshot.oilTempC
        case .timingAdvance: return snapshot.timingAdvanceDeg
        case .barometricPressure: return snapshot.barometricPressureKPa
        case .instantEfficiency:
            guard snapshot.speedKmH > 1 else { return 0 }
            return (snapshot.powerKW / snapshot.speedKmH) * 100.0
        }
    }
}
