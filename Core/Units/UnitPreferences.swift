import Foundation
import Observation

/// Display units for every human-readable quantity in the app.
///
/// Telemetry is always stored and recorded in SI units (km, km/h, °C, kW,
/// kWh/100 km). Only presentation converts, so switching units never rewrites
/// history or changes decoding.
public enum DistanceUnit: String, CaseIterable, Identifiable, Sendable {
    case kilometers
    case miles

    public var id: String { rawValue }
    public var symbol: String { self == .kilometers ? "km" : "mi" }
    public var displayName: String { self == .kilometers ? "Kilometers" : "Miles" }
    public var perHourSymbol: String { self == .kilometers ? "km/h" : "mph" }
}

public enum TemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case celsius
    case fahrenheit

    public var id: String { rawValue }
    public var symbol: String { self == .celsius ? "°C" : "°F" }
    public var displayName: String { self == .celsius ? "Celsius" : "Fahrenheit" }
}

public enum PowerUnit: String, CaseIterable, Identifiable, Sendable {
    case kilowatts
    case horsepower

    public var id: String { rawValue }
    public var symbol: String { self == .kilowatts ? "kW" : "hp" }
    public var displayName: String { self == .kilowatts ? "Kilowatts" : "Horsepower" }
}

@MainActor
@Observable
public final class UnitPreferences {
    public static let shared = UnitPreferences()

    private enum Key {
        static let distance = "unit.distance"
        static let temperature = "unit.temperature"
        static let power = "unit.power"
    }

    private let defaults: UserDefaults

    public var distanceUnit: DistanceUnit {
        didSet { defaults.set(distanceUnit.rawValue, forKey: Key.distance) }
    }

    public var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Key.temperature) }
    }

    public var powerUnit: PowerUnit {
        didSet { defaults.set(powerUnit.rawValue, forKey: Key.power) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default to the user's locale system rather than assuming metric; the EQA is
        // sold in both mph and km/h markets.
        let usesImperial = Locale.current.measurementSystem == .us
        distanceUnit =
            defaults.string(forKey: Key.distance).flatMap(DistanceUnit.init(rawValue:))
            ?? (usesImperial ? .miles : .kilometers)
        temperatureUnit =
            defaults.string(forKey: Key.temperature).flatMap(TemperatureUnit.init(rawValue:))
            ?? (usesImperial ? .fahrenheit : .celsius)
        powerUnit =
            defaults.string(forKey: Key.power).flatMap(PowerUnit.init(rawValue:))
            ?? .kilowatts
    }

    // MARK: - Conversion

    private static let kilometersPerMile = 1.609_344
    private static let kilowattsPerHorsepower = 0.745_699_872

    public func distanceValue(fromKilometers kilometers: Double) -> Double {
        distanceUnit == .kilometers ? kilometers : kilometers / Self.kilometersPerMile
    }

    public func speedValue(fromKilometersPerHour speed: Double) -> Double {
        distanceUnit == .kilometers ? speed : speed / Self.kilometersPerMile
    }

    public func temperatureValue(fromCelsius celsius: Double) -> Double {
        temperatureUnit == .celsius ? celsius : celsius * 9 / 5 + 32
    }

    public func powerValue(fromKilowatts kilowatts: Double) -> Double {
        powerUnit == .kilowatts ? kilowatts : kilowatts / Self.kilowattsPerHorsepower
    }

    /// Consumption is expressed per 100 of the selected distance unit.
    public func efficiencyValue(fromKilowattHoursPer100Kilometers value: Double) -> Double {
        distanceUnit == .kilometers ? value : value * Self.kilometersPerMile
    }

    public var efficiencyUnit: String {
        "kWh/100\(distanceUnit.symbol)"
    }

    // MARK: - Formatting

    public func distance(kilometers: Double, decimals: Int = 1) -> String {
        guard kilometers.isFinite else { return "--" }
        return String(format: "%.\(decimals)f %@", distanceValue(fromKilometers: kilometers), distanceUnit.symbol)
    }

    public func speed(kilometersPerHour: Double, decimals: Int = 1) -> String {
        guard kilometersPerHour.isFinite else { return "--" }
        return String(format: "%.\(decimals)f %@", speedValue(fromKilometersPerHour: kilometersPerHour), distanceUnit.perHourSymbol)
    }

    public func temperature(celsius: Double, decimals: Int = 0) -> String {
        guard celsius.isFinite else { return "--" }
        return String(format: "%.\(decimals)f %@", temperatureValue(fromCelsius: celsius), temperatureUnit.symbol)
    }

    public func power(kilowatts: Double, decimals: Int = 1) -> String {
        guard kilowatts.isFinite else { return "--" }
        return String(format: "%.\(decimals)f %@", powerValue(fromKilowatts: kilowatts), powerUnit.symbol)
    }

    public func energy(kilowattHours: Double, decimals: Int = 2) -> String {
        guard kilowattHours.isFinite else { return "--" }
        return String(format: "%.\(decimals)f kWh", kilowattHours)
    }

    public func efficiency(kilowattHoursPer100Kilometers: Double, decimals: Int = 1) -> String {
        guard kilowattHoursPer100Kilometers.isFinite else { return "--" }
        return String(
            format: "%.\(decimals)f %@", efficiencyValue(fromKilowattHoursPer100Kilometers: kilowattHoursPer100Kilometers), efficiencyUnit)
    }

    public func range(kilometers: Double, decimals: Int = 0) -> String {
        distance(kilometers: kilometers, decimals: decimals)
    }

    public var rangeUnit: String { distanceUnit.symbol }

    /// Converted value and unit for a dashboard/CarPlay metric tile.
    public func metricValue(_ metric: TelemetryMetric, value: Double) -> (value: Double, unit: String) {
        switch metric {
        case .speed, .frontLeftWheelSpeed, .frontRightWheelSpeed, .rearLeftWheelSpeed, .rearRightWheelSpeed:
            return (speedValue(fromKilometersPerHour: value), distanceUnit.perHourSymbol)
        case .power, .regenPower:
            return (powerValue(fromKilowatts: value), powerUnit.symbol)
        case .vehicleRange, .serviceDistance:
            return (distanceValue(fromKilometers: value), distanceUnit.symbol)
        case .instantEfficiency, .tripAverageConsumption:
            return (efficiencyValue(fromKilowattHoursPer100Kilometers: value), efficiencyUnit)
        case .batteryTemp, .batteryTempMin, .batteryTempMax, .coolantTemp, .intakeAirTemp, .ambientAirTemp, .oilTemp:
            return (temperatureValue(fromCelsius: value), temperatureUnit.symbol)
        default:
            return (value, metric.unitSymbol)
        }
    }

    /// Converted normalization range so dials/bar gauges keep the same visual scale.
    public func metricRange(_ metric: TelemetryMetric) -> ClosedRange<Double> {
        let source = metric.defaultRange
        let converted = metricValue(metric, value: source.lowerBound)
        let convertedUpper = metricValue(metric, value: source.upperBound).value
        // Power ranges span negative regen; convert each bound independently.
        return min(converted.value, convertedUpper)...max(converted.value, convertedUpper)
    }

    /// Unit label for a metric after conversion (e.g. "mph" instead of "km/h").
    public func metricUnit(_ metric: TelemetryMetric) -> String {
        metricValue(metric, value: 0).unit
    }

    public func resetToLocaleDefaults() {
        let usesImperial = Locale.current.measurementSystem == .us
        distanceUnit = usesImperial ? .miles : .kilometers
        temperatureUnit = usesImperial ? .fahrenheit : .celsius
        powerUnit = .kilowatts
    }
}
