import XCTest
import Combine
@testable import VoltLinkEngine

private final class CalibrationMockAdapter: OBDConnectionProtocol {
    var state: BLEConnectionState = .ready(deviceName: "Calibration Mock")
    weak var delegate: OBDConnectionDelegate?

    var responses: [String: Result<String, Error>] = [:]
    var sentCommands: [String] = []
    var deferredCommand: String?
    var pendingCompletion: ((Result<String, Error>) -> Void)?

    func connect(peripheralName: String?) {
        state = .ready(deviceName: "Calibration Mock")
        delegate?.obdConnectionStateDidChange(state)
    }

    func disconnect() {
        state = .disconnected
        delegate?.obdConnectionStateDidChange(.disconnected)
    }

    func sendCommand(_ command: String, completion: ((Result<String, Error>) -> Void)?) {
        sentCommands.append(command)
        if command == deferredCommand {
            pendingCompletion = completion
            return
        }
        let defaultResponse = command.hasPrefix("AT") ? "OK\r>" : "NO DATA\r>"
        let res = responses[command] ?? .success(defaultResponse)
        completion?(res)
    }
}

final class VehicleProfileCalibrationTests: XCTestCase {

    @MainActor
    func testStartupWaitsForRequiredAcknowledgementsBeforePolling() async {
        let mock = CalibrationMockAdapter()
        mock.deferredCommand = "AT SP 7"
        let manager = VehicleDataManager(connection: mock)
        defer { manager.stopPolling() }
        mock.connect(peripheralName: nil)
        XCTAssertEqual(manager.connectionState, .connecting(deviceName: "Calibration Mock"))
        XCTAssertEqual(mock.sentCommands.last, "AT SP 7")
        manager.startPolling()
        XCTAssertFalse(mock.sentCommands.contains("22010A"))

        mock.pendingCompletion?(.success("OK\r>"))
        XCTAssertEqual(manager.connectionState, mock.state)
        XCTAssertEqual(Array(mock.sentCommands.prefix(MercedesEQA250Profile().initializationCommands.count)), MercedesEQA250Profile().initializationCommands)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(mock.sentCommands.contains("22010A"))
    }

    @MainActor
    func testFailedStartupDisconnectsAndAllowsReconnect() {
        let mock = CalibrationMockAdapter()
        mock.responses["AT SP 7"] = .success("?\r>")
        let manager = VehicleDataManager(connection: mock)
        defer { manager.stopPolling() }
        mock.connect(peripheralName: nil)
        guard case .error(let message) = manager.connectionState else {
            return XCTFail("Failed setup must not report ready")
        }
        XCTAssertTrue(message.contains("AT SP 7"))
        XCTAssertEqual(mock.state, .disconnected)
        XCTAssertFalse(mock.sentCommands.contains("22010A"))

        mock.responses["AT SP 7"] = .success("OK\r>")
        mock.connect(peripheralName: nil)
        XCTAssertEqual(manager.connectionState, .ready(deviceName: "Calibration Mock"))
    }

    @MainActor
    func testRoutingFailureStopsRequestsAndDisconnects() async {
        let mock = CalibrationMockAdapter()
        mock.responses["AT SH 18DA59F1"] = .failure(NSError(domain: "Test", code: -2))
        let manager = VehicleDataManager(connection: mock)
        defer { manager.stopPolling() }
        manager.startPolling()
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(mock.state, .disconnected)
        guard case .error(let message) = manager.connectionState else {
            return XCTFail("Failed routing must be reported")
        }
        XCTAssertTrue(message.contains("AT SH 18DA59F1"))
        XCTAssertFalse(mock.sentCommands.contains("22010A"))
    }

    @MainActor
    func testPollingResumeDuringProfileInitializationIsRetained() async {
        let mock = CalibrationMockAdapter()
        mock.deferredCommand = "AT SP 7"
        let manager = VehicleDataManager(connection: mock)
        defer { manager.stopPolling() }
        manager.selectProfile(.mercedesEQA250)
        manager.startPolling()
        mock.pendingCompletion?(.success("OK\r>"))
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(mock.sentCommands.contains("22010A"))
    }

    @MainActor
    func testLateStartupAndPollingRepliesAreIgnoredAfterCancellation() async {
        let mock = CalibrationMockAdapter()
        mock.deferredCommand = "AT SP 7"
        let manager = VehicleDataManager(connection: mock)
        mock.connect(peripheralName: nil)
        mock.disconnect()
        let sentCount = mock.sentCommands.count
        mock.pendingCompletion?(.success("OK\r>"))
        XCTAssertEqual(mock.sentCommands.count, sentCount)
        XCTAssertEqual(manager.connectionState, .disconnected)

        mock.deferredCommand = "22010A"
        mock.pendingCompletion = nil
        mock.connect(peripheralName: nil)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNotNil(mock.pendingCompletion)
        manager.stopPolling()
        mock.pendingCompletion?(.success("18 DA F1 59 05 62 01 0A 0D 3E\r>"))
        XCTAssertEqual(manager.latestTelemetry.voltageV, 0)
        XCTAssertFalse(manager.liveMetrics.contains(.packVoltage))
    }

    @MainActor
    func testBundledZoeSessionAcknowledgementsAllowStartup() {
        for profileID in [VehicleProfileID.renaultZoe, .renaultZoeZE40] {
            let mock = CalibrationMockAdapter()
            mock.state = .disconnected
            mock.responses["1003"] = .success("50 03 00 32 01 F4\r>")
            mock.responses["10C0"] = .success("50 C0\r>")
            let manager = VehicleDataManager(connection: mock)
            manager.selectProfile(profileID)
            mock.connect(peripheralName: nil)
            XCTAssertEqual(manager.connectionState, .ready(deviceName: "Calibration Mock"))
            XCTAssertTrue(mock.sentCommands.contains(profileID == .renaultZoe ? "1003" : "10C0"))
            manager.stopPolling()
        }
    }

    @MainActor
    func testMissingVoltageThenSOCClearsEstimatedSession() async {
        let mock = CalibrationMockAdapter()
        mock.responses["03221E3B55555555"] = .success("62 1E 3B 05 F0\r>")
        mock.responses["0322028C55555555"] = .success("62 02 8C C8\r>")
        let manager = VehicleDataManager(connection: mock)
        manager.selectProfile(.volkswagenMEB)
        defer { manager.stopPolling() }
        manager.startPolling()
        for _ in 0..<20 {
            if manager.liveMetrics.contains(.soc) { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(manager.liveMetrics.contains(.packVoltage))
        XCTAssertTrue(manager.liveMetrics.contains(.soc))
        manager.stopPolling()

        let start = Date.now.addingTimeInterval(-30)
        for seconds in stride(from: 0, through: 30, by: 10) {
            manager.applyUpdate(.soc(50 + Double(seconds) * 0.004), timestamp: start.addingTimeInterval(Double(seconds)))
        }
        XCTAssertTrue(manager.chargingSession.isCharging)
        mock.responses["03221E3B55555555"] = .success("NO DATA\r>")
        mock.responses["0322028C55555555"] = .success("NO DATA\r>")
        manager.startPolling()
        for _ in 0..<30 {
            if !manager.liveMetrics.contains(.soc) { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(manager.liveMetrics.contains(.soc))
        XCTAssertFalse(manager.hasChargePower)
        XCTAssertFalse(manager.latestTelemetry.isCharging)
        XCTAssertFalse(manager.chargingSession.isCharging)
        XCTAssertEqual(manager.chargingSession.currentPowerKW, 0)
    }

    @MainActor
    func testEQACalibrationKeepsRetryingWhenOnlyATCommandsRespond() async {
        let mock = CalibrationMockAdapter()
        mock.responses = [
            "ATCRA 18DAF159": .success("OK\r>"),
            "AT SH 18DA59F1": .success("OK\r>")
        ]
        let manager = VehicleDataManager(connection: mock)
        defer { manager.stopPolling() }
        manager.startCalibration()
        for _ in 0..<20 {
            if !manager.isCalibrating { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(manager.isCalibrating)
        XCTAssertNil(manager.calibratedCommands)
        XCTAssertEqual(manager.calibrationSummary, "No reads responded")

        mock.sentCommands.removeAll()
        mock.responses["22010A"] = .success("18 DA F1 59 05 62 01 0A 0D 3E\r>")
        try? await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertTrue(mock.sentCommands.contains("22010A"))
        XCTAssertTrue(mock.sentCommands.contains("220210"))
        XCTAssertEqual(manager.latestTelemetry.voltageV, 339, accuracy: 0.01)
    }

    @MainActor
    func testEQACalibrationRetainsUndecodedCaptureDIDWithoutPublishingSOC() async {
        let mock = CalibrationMockAdapter()
        mock.responses = [
            "ATCRA 18DAF159": .success("OK\r>"),
            "AT SH 18DA59F1": .success("OK\r>"),
            "22010A": .success("18 DA F1 59 05 62 01 0A 0D 3E\r>")
        ]
        let manager = VehicleDataManager(connection: mock)
        defer { manager.stopPolling() }
        manager.startCalibration()
        for _ in 0..<20 {
            if !manager.isCalibrating { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(manager.isCalibrating)
        XCTAssertNil(manager.calibratedCommands)
        XCTAssertEqual(manager.calibrationSummary, "1 of 2 reads responded")

        manager.stopPolling()
        mock.responses["220210"] = .success("18 DA F1 59 10 0B 62 02 10 04 00 00\r18 DA F1 59 21 3E BC 00 00 00 AA AA\r>")
        manager.startCalibration()
        for _ in 0..<20 {
            if !manager.isCalibrating { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(manager.calibrationSummary, "2 of 2 reads responded")
        XCTAssertNil(manager.calibratedCommands)
        mock.sentCommands.removeAll()
        try? await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertGreaterThanOrEqual(mock.sentCommands.filter { $0 == "220210" }.count, 2)
        XCTAssertTrue(manager.liveMetrics.contains(.packVoltage))
        XCTAssertFalse(manager.liveMetrics.contains(.soc))
        XCTAssertNil(manager.latestTelemetry.socUpdatedAt)
        XCTAssertFalse(manager.hasChargePower)
        XCTAssertFalse(manager.latestTelemetry.isCharging)
    }

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
