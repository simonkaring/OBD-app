import XCTest

@testable import VoltLinkEngine

@MainActor
final class UnitPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "UnitPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDistanceAndSpeedConvertToMiles() {
        let units = UnitPreferences(defaults: defaults)
        units.distanceUnit = .miles

        XCTAssertEqual(units.distanceValue(fromKilometers: 160.9344), 100, accuracy: 0.0001)
        XCTAssertEqual(units.speedValue(fromKilometersPerHour: 100), 62.1371, accuracy: 0.0001)
        XCTAssertEqual(units.distance(kilometers: 10, decimals: 1), "6.2 mi")
        XCTAssertEqual(units.speed(kilometersPerHour: 100, decimals: 0), "62 mph")
    }

    func testTemperatureAndPowerConvert() {
        let units = UnitPreferences(defaults: defaults)
        units.temperatureUnit = .fahrenheit
        units.powerUnit = .horsepower

        XCTAssertEqual(units.temperatureValue(fromCelsius: 20), 68, accuracy: 0.0001)
        XCTAssertEqual(units.temperature(celsius: 20), "68 °F")
        XCTAssertEqual(units.powerValue(fromKilowatts: 100), 134.102, accuracy: 0.001)
        XCTAssertEqual(units.power(kilowatts: 100, decimals: 1), "134.1 hp")
    }

    func testEfficiencyUsesSelectedDistanceUnit() {
        let units = UnitPreferences(defaults: defaults)
        units.distanceUnit = .kilometers
        XCTAssertEqual(units.efficiency(kilowattHoursPer100Kilometers: 18.5), "18.5 kWh/100km")

        units.distanceUnit = .miles
        XCTAssertEqual(units.efficiencyUnit, "kWh/100mi")
        XCTAssertEqual(units.efficiencyValue(fromKilowattHoursPer100Kilometers: 10), 16.09344, accuracy: 0.0001)
        XCTAssertEqual(units.efficiency(kilowattHoursPer100Kilometers: 10, decimals: 1), "16.1 kWh/100mi")
    }

    func testMetricPresentationAndRangeConvertWithUnit() {
        let units = UnitPreferences(defaults: defaults)
        units.distanceUnit = .miles

        let speed = units.metricValue(.speed, value: 100)
        XCTAssertEqual(speed.value, 62.1371, accuracy: 0.0001)
        XCTAssertEqual(speed.unit, "mph")

        let range = units.metricRange(.speed)
        XCTAssertEqual(range.lowerBound, 0)
        XCTAssertEqual(range.upperBound, 124.2742, accuracy: 0.001)

        let power = units.metricRange(.power)
        XCTAssertEqual(power.lowerBound, -50, accuracy: 0.0001)
        XCTAssertEqual(power.upperBound, 150, accuracy: 0.0001)

        XCTAssertEqual(units.metricUnit(.batteryTemp), "°C", "Temperature conversion only applies when selected")
        units.temperatureUnit = .fahrenheit
        XCTAssertEqual(units.metricUnit(.batteryTemp), "°F")
    }

    func testSelectionsPersistAcrossInstances() {
        let first = UnitPreferences(defaults: defaults)
        first.distanceUnit = .miles
        first.temperatureUnit = .fahrenheit
        first.powerUnit = .horsepower

        let restored = UnitPreferences(defaults: defaults)
        XCTAssertEqual(restored.distanceUnit, .miles)
        XCTAssertEqual(restored.temperatureUnit, .fahrenheit)
        XCTAssertEqual(restored.powerUnit, .horsepower)
    }
}
