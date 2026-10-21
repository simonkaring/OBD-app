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
}
