import XCTest

@testable import VoltLinkEngine

final class LiveActivityContentTests: XCTestCase {
    private func snapshot(
        soc: Double = 62,
        powerKW: Double = 12,
        speedKmH: Double = 90,
        rangeKm: Double? = 240,
        distanceKm: Double = 4.2,
        consumption: Double? = 17.5,
        startedAt: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        units: SharedDisplayUnits = SharedDisplayUnits()
    ) -> SharedTelemetrySnapshot {
        SharedTelemetrySnapshot(
            vehicleName: "Mercedes-Benz EQA 250",
            socPct: soc,
            powerKW: powerKW,
            speedKmH: speedKmH,
            rangeKm: rangeKm,
            isCharging: false,
            isConnected: true,
            isTripActive: true,
            distanceKm: distanceKm,
            averageConsumptionKWhPer100Km: consumption,
            activeSessionStartedAt: startedAt,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            units: units)
    }

    func testLegacyContentDecodesWithoutRangeConsumptionOrUnits() throws {
        let legacy = """
            {"mode":"trip","socPct":62,"powerKW":12,"speedKmH":90,"distanceKm":4.2,"startedAt":0}
            """
        let content = try JSONDecoder().decode(
            VoltLinkActivityContent.self, from: XCTUnwrap(legacy.data(using: .utf8)))

        XCTAssertEqual(content.mode, .trip)
        XCTAssertEqual(content.speedKmH, 90)
        XCTAssertNil(content.rangeKm)
        XCTAssertNil(content.averageConsumptionKWhPer100Km)
        XCTAssertEqual(content.units, SharedDisplayUnits())
        XCTAssertFalse(content.isDemoMode)
    }

    func testContentRoundTripsRangeAndConsumption() throws {
        let content = VoltLinkActivityContent(
            mode: .trip,
            socPct: 62,
            powerKW: 12,
            speedKmH: 90,
            distanceKm: 4.2,
            rangeKm: 240,
            averageConsumptionKWhPer100Km: 17.5,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let decoded = try JSONDecoder().decode(VoltLinkActivityContent.self, from: JSONEncoder().encode(content))
        XCTAssertEqual(decoded, content)
    }

    func testMakeUsesRecorderStartAndCopiesTripValues() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let content = VoltLinkActivityContent.make(mode: .trip, snapshot: snapshot(), startedAt: start)

        XCTAssertEqual(content.startedAt, start, "Elapsed must count from the trip start, not from the activity")
        XCTAssertEqual(content.mode, .trip)
        XCTAssertEqual(content.rangeKm, 240)
        XCTAssertEqual(content.averageConsumptionKWhPer100Km, 17.5)
        XCTAssertEqual(content.distanceKm, 4.2)
    }

    func testChargingContentDropsTripConsumptionAndKeepsPower() {
        let content = VoltLinkActivityContent.make(mode: .charging, snapshot: snapshot(powerKW: 42), startedAt: .now)

        XCTAssertNil(content.averageConsumptionKWhPer100Km, "A charging card must not show the previous trip's average")
        XCTAssertEqual(content.powerKW, 42)
    }

    func testMissingConsumptionStaysNilInsteadOfZero() {
        let content = VoltLinkActivityContent.make(
            mode: .trip, snapshot: snapshot(consumption: nil), startedAt: .now)

        XCTAssertNil(content.averageConsumptionKWhPer100Km)
    }
}
