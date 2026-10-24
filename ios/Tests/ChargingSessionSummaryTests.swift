import XCTest

@testable import VoltLinkEngine

final class ChargingSessionSummaryTests: XCTestCase {
    func testDurationFormatsMinutesAndHours() {
        XCTAssertEqual(ChargingSessionSummary.duration(45), "<1m")
        XCTAssertEqual(ChargingSessionSummary.duration(480), "8m")
        XCTAssertEqual(ChargingSessionSummary.duration(2_400), "40m")
        XCTAssertEqual(ChargingSessionSummary.duration(3_660), "1h 01m")
        XCTAssertEqual(ChargingSessionSummary.duration(7_200), "2h 00m")
    }

    func testDurationRejectsNonFiniteIntervals() {
        XCTAssertEqual(ChargingSessionSummary.duration(.nan), "<1m")
        XCTAssertEqual(ChargingSessionSummary.duration(.infinity), "<1m")
    }

    func testAveragePowerMatchesPersistedRatio() {
        // 28 kWh over a 40 minute session is the demo session's 42 kW average.
        let average = ChargingSessionSummary.averagePowerKW(energyKWh: 28, over: 2_400)
        XCTAssertEqual(try XCTUnwrap(average), 42, accuracy: 0.001)
    }

    func testAveragePowerNeedsEnergyAndTime() {
        XCTAssertNil(ChargingSessionSummary.averagePowerKW(energyKWh: 0, over: 600))
        XCTAssertNil(ChargingSessionSummary.averagePowerKW(energyKWh: 10, over: 0))
        XCTAssertNil(ChargingSessionSummary.averagePowerKW(energyKWh: .nan, over: 600))
        XCTAssertNil(ChargingSessionSummary.averagePowerKW(energyKWh: 10, over: .nan))
    }
}
