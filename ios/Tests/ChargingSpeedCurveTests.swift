import XCTest

@testable import VoltLinkEngine

final class ChargingSpeedCurveTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testSessionCurveOrdersSamplesAndNormalisesToMinutes() {
        let samples = [
            ChargingSampleModel(timestamp: start.addingTimeInterval(600), socPct: 60, powerKW: 40),
            ChargingSampleModel(timestamp: start, socPct: 40, powerKW: 70),
            ChargingSampleModel(timestamp: start.addingTimeInterval(300), socPct: 50, powerKW: 55),
        ]

        let curve = ChargingSpeedCurve.session(samples)

        XCTAssertEqual(curve.map(\.minute), [0, 5, 10])
        XCTAssertEqual(curve.map(\.powerKW), [70, 55, 40])
    }

    func testSessionCurveNeedsTwoSamples() {
        XCTAssertTrue(ChargingSpeedCurve.session([]).isEmpty)

        let single = ChargingSampleModel(timestamp: start, socPct: 30, powerKW: 12)
        XCTAssertTrue(ChargingSpeedCurve.session([single]).isEmpty, "A single point cannot draw a curve")
    }

    func testCurveClampsNegativePowerToZero() {
        let samples = [
            ChargingSampleModel(timestamp: start, socPct: 40, powerKW: -5),
            ChargingSampleModel(timestamp: start.addingTimeInterval(60), socPct: 41, powerKW: 30),
        ]

        XCTAssertEqual(ChargingSpeedCurve.session(samples).map(\.powerKW), [0, 30])
    }

    func testLiveCurveCapsPointCountAndKeepsEndpoints() {
        let history = (0..<1_000).map { index in
            ChargingDataPoint(
                timestamp: start.addingTimeInterval(Double(index) * 2),
                powerKW: 100 - Double(index) / 20,
                soc: 20 + Double(index) / 100,
                packVoltage: 400,
                packCurrent: -100)
        }

        let curve = ChargingSpeedCurve.live(history)

        XCTAssertEqual(curve.count, 180)
        XCTAssertEqual(curve.first?.minute, 0)
        XCTAssertEqual(curve.last?.minute ?? 0, 1_998 / 60, accuracy: 0.001)
        XCTAssertEqual(curve.last?.powerKW ?? 0, history.last?.powerKW ?? 0, accuracy: 0.001)
    }

    func testLiveCurveNeedsTwoPoints() {
        let point = ChargingDataPoint(timestamp: start, powerKW: 50, soc: 30, packVoltage: 400, packCurrent: -125)
        XCTAssertTrue(ChargingSpeedCurve.live([point]).isEmpty)
    }
}
