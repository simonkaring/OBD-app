import XCTest
import Combine
@testable import VoltLinkEngine

private final class CalibrationMockAdapter: OBDConnectionProtocol {
    var state: BLEConnectionState = .ready(deviceName: "Calibration Mock")
    weak var delegate: OBDConnectionDelegate?

    var responses: [String: Result<String, Error>] = [:]

    func connect(peripheralName: String?) {
        state = .ready(deviceName: "Calibration Mock")
        delegate?.obdConnectionStateDidChange(state)
    }

    func disconnect() {
        state = .disconnected
        delegate?.obdConnectionStateDidChange(.disconnected)
    }

    func sendCommand(_ command: String, completion: ((Result<String, Error>) -> Void)?) {
        let res = responses[command] ?? .success("NO DATA\r\n>")
        completion?(res)
    }
}

final class VehicleProfileCalibrationTests: XCTestCase {

    @MainActor
    func testProfileCalibrationFiltersUnsupportedCommands() async {
        let mock = CalibrationMockAdapter()
        mock.responses = [
            "010D": .success("41 0D 32\r\n>"), // Speed 50 km/h (Supported)
            "010C": .success("NO DATA\r\n>"),   // RPM (Unsupported)
            "0105": .failure(NSError(domain: "Test", code: -1, userInfo: nil)), // Coolant (Timeout/Error)
            "0142": .success("41 42 30 D4\r\n>") // 12V (Supported)
        ]

        let manager = VehicleDataManager(connection: mock)
        manager.selectProfile(.genericOBD2)

        XCTAssertNil(manager.calibratedCommands)
        XCTAssertFalse(manager.isCalibrating)

        manager.startCalibration()
        XCTAssertTrue(manager.isCalibrating)

        // Wait briefly for the async calibration task to complete
        for _ in 0..<20 {
            if !manager.isCalibrating { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertFalse(manager.isCalibrating)
        guard let calibrated = manager.calibratedCommands else {
            XCTFail("calibratedCommands should not be nil after calibration")
            return
        }

        XCTAssertTrue(calibrated.contains("010D"))
        XCTAssertTrue(calibrated.contains("0142"))
        XCTAssertFalse(calibrated.contains("010C"))
        XCTAssertFalse(calibrated.contains("0105"))
        XCTAssertNotNil(manager.calibrationSummary)
        XCTAssertEqual(manager.latestTelemetry.speedKmH, 50.0)
    }

    @MainActor
    func testResetCalibrationClearsCalibratedCommands() async {
        let mock = CalibrationMockAdapter()
        mock.responses = [
            "010D": .success("41 0D 32\r\n>")
        ]

        let manager = VehicleDataManager(connection: mock)
        manager.selectProfile(.genericOBD2)
        manager.startCalibration()

        for _ in 0..<20 {
            if !manager.isCalibrating { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertNotNil(manager.calibratedCommands)
        manager.resetCalibration()
        XCTAssertNil(manager.calibratedCommands)
        XCTAssertNil(manager.calibrationSummary)
    }

    @MainActor
    func testProfileSelectionResetsCalibration() async {
        let mock = CalibrationMockAdapter()
        mock.responses = [
            "010D": .success("41 0D 32\r\n>")
        ]

        let manager = VehicleDataManager(connection: mock)
        manager.selectProfile(.genericOBD2)
        manager.startCalibration()

        for _ in 0..<20 {
            if !manager.isCalibrating { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertNotNil(manager.calibratedCommands)
        manager.selectProfile(.mercedesEQA250)
        XCTAssertNil(manager.calibratedCommands)
        XCTAssertNil(manager.calibrationSummary)
    }
}
