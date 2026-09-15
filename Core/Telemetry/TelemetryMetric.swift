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
    case tripAverageConsumption
    case regenPower
    case vehicleRange

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
        case .instantEfficiency: return "Live Consumption"
        case .tripAverageConsumption: return "Trip Average Consumption"
        case .regenPower: return "Regen Power"
        case .vehicleRange: return "Vehicle Range"
        }
    }

    public var unitSymbol: String {
        switch self {
        case .speed: return "km/h"
        case .power, .regenPower: return "kW"
        case .soc, .soh, .fuelLevel, .throttlePosition, .engineLoad: return "%"
        case .batteryTemp, .coolantTemp, .intakeAirTemp, .batteryTempMin, .batteryTempMax, .ambientAirTemp, .oilTemp: return "°C"
        case .aux12V, .packVoltage: return "V"
        case .motorRpm: return "RPM"
        case .motorTorque: return "Nm"
        case .packCurrent: return "A"
        case .maf: return "g/s"
        case .manifoldPressure, .barometricPressure: return "kPa"
        case .timingAdvance: return "°"
        case .instantEfficiency, .tripAverageConsumption: return "kWh/100km"
        case .vehicleRange: return "km"
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
        case .instantEfficiency, .tripAverageConsumption: return "leaf.fill"
        case .regenPower: return "arrow.down.forward.and.arrow.up.backward"
        case .vehicleRange: return "point.topleft.down.to.point.bottomright.curvepath"
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
        case .instantEfficiency, .tripAverageConsumption: return -40...40
        case .regenPower: return 0...100
        case .vehicleRange: return 0...600
        }
    }

    /// Decimal places to render at in the numeric tile — a bare `%.0f` rounds
    /// small-magnitude values like 12.6V to an indistinguishable "13".
    public var decimalPlaces: Int {
        switch self {
        case .packVoltage, .aux12V, .instantEfficiency, .tripAverageConsumption, .regenPower: return 1
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
            guard snapshot.speedKmH >= 5 else { return 0 }
            return (snapshot.powerKW / snapshot.speedKmH) * 100.0
        case .tripAverageConsumption: return snapshot.tripAverageConsumption ?? 0
        case .regenPower:
            return snapshot.speedKmH >= 1 && !snapshot.isCharging ? max(0, -snapshot.powerKW) : 0
        case .vehicleRange: return snapshot.vehicleRangeKm ?? 0
        }
    }

    /// Derived metrics share the availability of their inputs, including after a read fails.
    public static func includingDerivedMetrics(_ metrics: Set<Self>) -> Set<Self> {
        var result = metrics.subtracting([.instantEfficiency, .regenPower])
        if result.isSuperset(of: [.speed, .power]) {
            result.formUnion([.instantEfficiency, .regenPower])
        }
        return result
    }

    /// Used by tiles, CarPlay and individual chart samples so missing data isn't plotted as zero.
    public func isAvailable(in snapshot: TelemetrySnapshot, liveMetrics: Set<Self>, isDemoMode: Bool = false, at date: Date? = nil) -> Bool {
        if self == .tripAverageConsumption { return snapshot.tripAverageConsumption != nil }
        guard isDemoMode || liveMetrics.contains(self) else { return false }
        let date = date ?? snapshot.timestamp
        func fresh(_ timestamp: Date?) -> Bool {
            timestamp.map { (0...15).contains(date.timeIntervalSince($0)) } ?? false
        }
        switch self {
        case .instantEfficiency:
            return fresh(snapshot.speedUpdatedAt) && fresh(snapshot.powerUpdatedAt) && snapshot.speedKmH >= 5 && !snapshot.isCharging
        case .regenPower:
            return fresh(snapshot.speedUpdatedAt) && fresh(snapshot.powerUpdatedAt)
        case .vehicleRange:
            return snapshot.vehicleRangeKm != nil && fresh(snapshot.vehicleRangeUpdatedAt)
        default: return true
        }
    }
}
