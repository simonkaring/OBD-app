import XCTest

@testable import VoltLinkEngine

final class SharedTelemetryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SharedTelemetryStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testSnapshotRoundTripsThroughDefaults() {
        let snapshot = SharedTelemetrySnapshot(
            vehicleName: "Mercedes-Benz EQA 250",
            socPct: 64,
            powerKW: 42.5,
            speedKmH: 88,
            rangeKm: 310,
            isCharging: true,
            isConnected: true,
            isDemoMode: false,
            isTripActive: false,
            distanceKm: 0,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        SharedTelemetryStore.save(snapshot, defaults: defaults)
        XCTAssertEqual(SharedTelemetryStore.load(defaults: defaults), snapshot)
    }

    func testSnapshotMissingNewerFieldsStillDecodes() throws {
        let legacy = """
            {"vehicleName":"EQA","socPct":55,"powerKW":0,"isCharging":false,"isConnected":true,"isDemoMode":false,"isTripActive":false,"distanceKm":0,"updatedAt":0}
            """
        let data = try XCTUnwrap(legacy.data(using: .utf8))
        defaults.set(data, forKey: "shared.telemetry.snapshot")

        let snapshot = try XCTUnwrap(SharedTelemetryStore.load(defaults: defaults))
        XCTAssertEqual(snapshot.socPct, 55)
        XCTAssertEqual(snapshot.speedKmH, 0)
        XCTAssertNil(snapshot.rangeKm)
    }

    func testMissingSnapshotLoadsNil() {
        XCTAssertNil(SharedTelemetryStore.load(defaults: defaults))
    }

    func testSnapshotMissingUnitsDefaultsToMetric() throws {
        let legacy = """
            {"vehicleName":"EQA","socPct":55,"updatedAt":0}
            """
        defaults.set(try XCTUnwrap(legacy.data(using: .utf8)), forKey: "shared.telemetry.snapshot")

        let snapshot = try XCTUnwrap(SharedTelemetryStore.load(defaults: defaults))
        XCTAssertEqual(snapshot.units, SharedDisplayUnits())
        XCTAssertEqual(snapshot.units.distanceSymbol, "km")
        XCTAssertEqual(snapshot.units.speedSymbol, "km/h")
        XCTAssertEqual(snapshot.units.powerSymbol, "kW")
    }

    func testSnapshotRoundTripsImperialUnits() {
        let units = SharedDisplayUnits(distance: .miles, power: .horsepower)
        let snapshot = SharedTelemetrySnapshot(vehicleName: "EQA", socPct: 50, powerKW: 100, speedKmH: 100, distanceKm: 10, units: units)

        SharedTelemetryStore.save(snapshot, defaults: defaults)
        XCTAssertEqual(SharedTelemetryStore.load(defaults: defaults)?.units, units)
        XCTAssertEqual(units.speed(kilometersPerHour: 100), 100 / 1.609_344, accuracy: 0.000_1)
        XCTAssertEqual(units.distance(kilometers: 1.609_344), 1, accuracy: 0.000_1)
        XCTAssertEqual(units.power(kilowatts: 74.569_987_2), 100, accuracy: 0.000_1)
    }

    func testStaleSnapshotIsNotServedForWidgets() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fresh = SharedTelemetrySnapshot(vehicleName: "EQA", socPct: 50, updatedAt: now.addingTimeInterval(-30))
        let stale = SharedTelemetrySnapshot(vehicleName: "EQA", socPct: 50, updatedAt: now.addingTimeInterval(-600))

        XCTAssertFalse(fresh.isStale(at: now))
        XCTAssertTrue(stale.isStale(at: now))

        SharedTelemetryStore.save(stale, defaults: defaults)
        XCTAssertNotNil(SharedTelemetryStore.load(defaults: defaults))
        XCTAssertNil(SharedTelemetryStore.loadFresh(now: now, defaults: defaults), "A snapshot the app stopped refreshing must not render as live")

        SharedTelemetryStore.save(fresh, defaults: defaults)
        XCTAssertNotNil(SharedTelemetryStore.loadFresh(now: now, defaults: defaults))
    }

    func testSnapshotWithoutUpdatedAtCountsAsStale() throws {
        let legacy = """
            {"vehicleName":"EQA","socPct":55}
            """
        defaults.set(try XCTUnwrap(legacy.data(using: .utf8)), forKey: "shared.telemetry.snapshot")

        XCTAssertNil(SharedTelemetryStore.loadFresh(defaults: defaults))
    }
}
