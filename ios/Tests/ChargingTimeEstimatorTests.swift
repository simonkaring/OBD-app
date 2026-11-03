import XCTest

@testable import VoltLinkEngine

final class ChargingTimeEstimatorTests: XCTestCase {
    func testACChargeHoldsItsRate() throws {
        let seconds = try XCTUnwrap(
            ChargingTimeEstimator.secondsToTarget(
                currentSOC: 50, targetSOC: 100, currentPowerKW: 11, capacityKWh: 60))
        XCTAssertEqual(seconds, 30.0 / 11.0 * 3600.0, accuracy: 1)
    }

    func testDCChargeTakesLongerAboveEightyPercent() throws {
        let seconds = try XCTUnwrap(
            ChargingTimeEstimator.secondsToTarget(
                currentSOC: 70, targetSOC: 100, currentPowerKW: 100, capacityKWh: 75))
        // Dividing once by 100 kW would claim 810 s for the same 22.5 kWh.
        XCTAssertGreaterThan(seconds, 810)
        XCTAssertLessThan(seconds, ChargingTimeEstimator.maximumEstimate)
    }

    func testLastTenPercentIsNotInstantOnDC() throws {
        let seconds = try XCTUnwrap(
            ChargingTimeEstimator.secondsToTarget(
                currentSOC: 90, targetSOC: 100, currentPowerKW: 100, capacityKWh: 75))
        // A constant-rate answer would be 675 s.
        XCTAssertGreaterThan(seconds, 675 * 1.3)
    }

    func testTopTwentyPercentCostsMoreThanTwiceTheConstantRate() throws {
        let seconds = try XCTUnwrap(
            ChargingTimeEstimator.secondsToTarget(
                currentSOC: 80, targetSOC: 100, currentPowerKW: 100, capacityKWh: 75))
        XCTAssertGreaterThan(seconds, 2 * 540)
    }

    func testReachedTargetReturnsZero() throws {
        let seconds = try XCTUnwrap(
            ChargingTimeEstimator.secondsToTarget(
                currentSOC: 80, targetSOC: 80, currentPowerKW: 50, capacityKWh: 60))
        XCTAssertEqual(seconds, 0)
    }

    func testRejectsUnusableInputs() {
        XCTAssertNil(ChargingTimeEstimator.secondsToTarget(currentSOC: 50, targetSOC: 80, currentPowerKW: 0, capacityKWh: 60))
        XCTAssertNil(ChargingTimeEstimator.secondsToTarget(currentSOC: 50, targetSOC: 80, currentPowerKW: 50, capacityKWh: 0))
        XCTAssertNil(ChargingTimeEstimator.secondsToTarget(currentSOC: -5, targetSOC: 80, currentPowerKW: 50, capacityKWh: 60))
        XCTAssertNil(ChargingTimeEstimator.secondsToTarget(currentSOC: 50, targetSOC: 120, currentPowerKW: 50, capacityKWh: 60))
        XCTAssertNil(ChargingTimeEstimator.secondsToTarget(currentSOC: .nan, targetSOC: 80, currentPowerKW: 50, capacityKWh: 60))
    }

    func testObservedFallingCurveProjectsThatSlope() throws {
        let curve = [
            ChargingCurveSample(socPct: 60, powerKW: 100),
            ChargingCurveSample(socPct: 70, powerKW: 70),
        ]
        XCTAssertEqual(try XCTUnwrap(ChargingTimeEstimator.observedTaperSlope(curve: curve)), -3.0, accuracy: 0.001)
        let projected = ChargingTimeEstimator.projectedPowerKW(
            atSOC: 75, currentSOC: 70, currentPowerKW: 70, observedCurve: curve)
        XCTAssertEqual(projected, 55, accuracy: 0.001)
    }

    func testFlatCurveFallsBackToDefaultTaper() {
        let curve = [
            ChargingCurveSample(socPct: 60, powerKW: 90),
            ChargingCurveSample(socPct: 70, powerKW: 90),
        ]
        XCTAssertNil(ChargingTimeEstimator.observedTaperSlope(curve: curve))
        let at85 = ChargingTimeEstimator.projectedPowerKW(
            atSOC: 85, currentSOC: 80, currentPowerKW: 100, observedCurve: curve)
        let at95 = ChargingTimeEstimator.projectedPowerKW(
            atSOC: 95, currentSOC: 80, currentPowerKW: 100, observedCurve: curve)
        XCTAssertLessThan(at85, 100)
        XCTAssertLessThan(at95, at85)
        XCTAssertGreaterThanOrEqual(at95, 100 * ChargingTimeEstimator.taperFloorRatio)
    }

    func testACChargingIgnoresTaperProjection() {
        let projected = ChargingTimeEstimator.projectedPowerKW(
            atSOC: 95, currentSOC: 80, currentPowerKW: 11, observedCurve: [])
        XCTAssertEqual(projected, 11, accuracy: 0.001)
    }
}
