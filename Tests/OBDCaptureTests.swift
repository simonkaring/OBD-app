import XCTest
@testable import VoltLinkEngine

final class OBDCaptureTests: XCTestCase {
    @MainActor
    func testCaptureKeepsAll600CommandsWhileLiveTailStaysAt500AndReopensAfterStop() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = BluetoothManager(commandWriter: { _ in }, scheduleRecovery: { _ in }, captureDirectory: directory)
        defer { manager.stopCapture() }

        manager.sendCommand("BEFORE_CAPTURE", completion: nil)
        manager.receiveResponseChunk("old response\r>")
        XCTAssertFalse(manager.isCapturing)
        XCTAssertNil(manager.captureFileURL)

        manager.startCapture(vehicleContext: "Mercedes-Benz EQA 250 (2021)")
        XCTAssertTrue(manager.isCapturing)
        XCTAssertNil(manager.captureError)
        let url = try XCTUnwrap(manager.captureFileURL)
        for index in 0..<600 {
            manager.sendCommand(String(format: "CMD%04d", index), completion: nil)
            manager.receiveResponseChunk("response \(index)\r>")
        }

        XCTAssertEqual(manager.log.count, 500)
        XCTAssertEqual(manager.log.first?.sent, "CMD0100")
        XCTAssertEqual(manager.log.last?.sent, "CMD0599")
        let captured = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(captured.contains("# Vehicle: Mercedes-Benz EQA 250 (2021)"))
        XCTAssertNotNil(captured.range(of: #"# Started: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z"#, options: .regularExpression))
        XCTAssertNotNil(captured.range(of: #"\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\] TX: CMD0000"#, options: .regularExpression))
        XCTAssertTrue(captured.contains("TX: CMD0000\nresponse 0\r>\n\n"))
        XCTAssertTrue(captured.hasSuffix("TX: CMD0599\nresponse 599\r>\n\n"))
        XCTAssertEqual(captured.components(separatedBy: "] TX: ").count - 1, 600)
        XCTAssertFalse(captured.contains("BEFORE_CAPTURE"))

        manager.clearLog()
        XCTAssertTrue(manager.log.isEmpty)
        XCTAssertTrue(manager.isCapturing)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), captured)
        manager.stopCapture()
        manager.stopCapture()
        XCTAssertFalse(manager.isCapturing)
        XCTAssertNil(manager.captureError)
        manager.sendCommand("AFTER_STOP", completion: nil)
        manager.receiveResponseChunk("not captured\r>")
        XCTAssertEqual(manager.log.last?.sent, "AFTER_STOP")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), captured)

        let reopened = BluetoothManager(commandWriter: { _ in }, scheduleRecovery: { _ in }, captureDirectory: directory)
        XCTAssertFalse(reopened.isCapturing)
        XCTAssertTrue(reopened.log.isEmpty)
        XCTAssertEqual(reopened.captureFileURL, url)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(reopened.captureFileURL), encoding: .utf8), captured)
    }

    @MainActor
    func testMultilineResponsesSurviveConnectionResetAndDisconnectDoesNotStopCapture() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = BluetoothManager(commandWriter: { _ in }, scheduleRecovery: { _ in }, captureDirectory: directory)
        defer { manager.stopCapture() }
        manager.startCapture(vehicleContext: "Generic OBD-II")
        let url = try XCTUnwrap(manager.captureFileURL)
        let firstChunk = "22F190\r\r\n7E8 10 14 62 F1 90 57 44 44\r"
        let lastChunk = "\n7E8 21 31 32 33 34 35 36 37\r\n>\r\n"
        manager.sendCommand("22F190", completion: nil)
        manager.receiveResponseChunk(firstChunk)
        XCTAssertTrue(manager.log.isEmpty)
        manager.receiveResponseChunk(lastChunk)
        XCTAssertEqual(manager.log.last?.response, firstChunk + lastChunk)

        // The test writer and ready state simulate transport reuse after reset.
        manager.resetConnectionState()
        XCTAssertTrue(manager.isCapturing)
        manager.sendCommand("AT RV", completion: nil)
        manager.receiveResponseChunk("12.6V\r>")
        manager.sendCommand("FAILED_COMMAND", completion: nil)
        let error = NSError(domain: "OBDCaptureTests", code: -4, userInfo: [NSLocalizedDescriptionKey: "Adapter rejected command"])
        manager.completeInFlight(.failure(error), rawResponse: nil)
        manager.disconnect()
        XCTAssertTrue(manager.isCapturing)
        manager.stopCapture()

        let captured = try Data(contentsOf: url)
        XCTAssertNotNil(captured.range(of: Data("TX: 22F190\n\(firstChunk)\(lastChunk)\n\n".utf8)))
        XCTAssertNotNil(captured.range(of: Data("TX: AT RV\n12.6V\r>\n\n".utf8)))
        XCTAssertNotNil(captured.range(of: Data("TX: FAILED_COMMAND\nERROR: Adapter rejected command\n\n".utf8)))
    }

    @MainActor
    func testStartFailurePreservesPreviousCaptureAndSuccessfulRestartReplacesIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = BluetoothManager(commandWriter: { _ in }, scheduleRecovery: { _ in }, captureDirectory: directory)
        original.startCapture(vehicleContext: "Previous vehicle")
        original.sendCommand("PREVIOUS", completion: nil)
        original.receiveResponseChunk("keep this\r>")
        original.stopCapture()
        let url = try XCTUnwrap(original.captureFileURL)
        let previous = try Data(contentsOf: url)

        var failOpen = true
        let manager = BluetoothManager(
            commandWriter: { _ in }, scheduleRecovery: { _ in }, captureDirectory: directory,
            openCaptureFile: { url in
                if failOpen { throw CocoaError(.fileWriteNoPermission) }
                return try FileHandle(forWritingTo: url)
            }
        )
        defer { manager.stopCapture() }
        manager.startCapture(vehicleContext: "Replacement vehicle")
        XCTAssertFalse(manager.isCapturing)
        XCTAssertNotNil(manager.captureError)
        XCTAssertEqual(manager.captureFileURL, url)
        XCTAssertEqual(try Data(contentsOf: url), previous)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [url.lastPathComponent])

        failOpen = false
        manager.startCapture(vehicleContext: "Replacement vehicle")
        XCTAssertTrue(manager.isCapturing)
        XCTAssertNil(manager.captureError)
        manager.sendCommand("REPLACEMENT", completion: nil)
        manager.receiveResponseChunk("new response\r>")
        // Starting an already active capture must not truncate it.
        manager.startCapture(vehicleContext: "Ignored vehicle")
        manager.stopCapture()
        let replacement = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(replacement.contains("# Vehicle: Replacement vehicle"))
        XCTAssertTrue(replacement.contains("TX: REPLACEMENT\nnew response\r>\n\n"))
        XCTAssertFalse(replacement.contains("PREVIOUS"))
        XCTAssertFalse(replacement.contains("Ignored vehicle"))
    }

    @MainActor
    func testInvalidCaptureDirectorySurfacesStartErrorWithoutAdvertisingAFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("not-a-directory")
        let contents = Data("preserve me".utf8)
        try contents.write(to: blocker)
        let manager = BluetoothManager(commandWriter: { _ in }, scheduleRecovery: { _ in }, captureDirectory: blocker)
        manager.startCapture(vehicleContext: "Test vehicle")
        XCTAssertFalse(manager.isCapturing)
        XCTAssertNil(manager.captureFileURL)
        XCTAssertNotNil(manager.captureError)
        XCTAssertEqual(try Data(contentsOf: blocker), contents)
    }

    @MainActor
    func testWriteFailureStopsCaptureAndKeepsPartialFileAndLiveLogging() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var handle: FileHandle?
        let manager = BluetoothManager(
            commandWriter: { _ in }, scheduleRecovery: { _ in }, captureDirectory: directory,
            openCaptureFile: { url in
                let opened = try FileHandle(forWritingTo: url)
                handle = opened
                return opened
            }
        )
        defer { manager.stopCapture() }
        manager.startCapture(vehicleContext: "Test vehicle")
        let url = try XCTUnwrap(manager.captureFileURL)
        manager.sendCommand("SAVED", completion: nil)
        manager.receiveResponseChunk("saved response\r>")
        let partial = try Data(contentsOf: url)

        try XCTUnwrap(handle).close()
        manager.sendCommand("WRITE_FAILURE", completion: nil)
        manager.receiveResponseChunk("still in live log\r>")
        XCTAssertFalse(manager.isCapturing)
        XCTAssertNotNil(manager.captureError)
        XCTAssertEqual(manager.captureFileURL, url)
        XCTAssertEqual(try Data(contentsOf: url), partial)
        XCTAssertEqual(manager.log.last?.sent, "WRITE_FAILURE")
        manager.sendCommand("AFTER_FAILURE", completion: nil)
        manager.receiveResponseChunk("live logging continues\r>")
        XCTAssertEqual(manager.log.last?.sent, "AFTER_FAILURE")
        XCTAssertEqual(try Data(contentsOf: url), partial)

        let reopened = BluetoothManager(commandWriter: { _ in }, scheduleRecovery: { _ in }, captureDirectory: directory)
        XCTAssertEqual(reopened.captureFileURL, url)
    }

    @MainActor
    func testDeinitClosesActiveCaptureAndLeavesItAvailable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var handle: FileHandle?
        var manager: BluetoothManager? = BluetoothManager(
            commandWriter: { _ in }, scheduleRecovery: { _ in }, captureDirectory: directory,
            openCaptureFile: { url in
                let opened = try FileHandle(forWritingTo: url)
                handle = opened
                return opened
            }
        )
        manager?.startCapture(vehicleContext: "Test vehicle")
        manager?.sendCommand("BEFORE_DEINIT", completion: nil)
        manager?.receiveResponseChunk("saved response\r>")
        let url = try XCTUnwrap(manager?.captureFileURL)
        weak let releasedManager = manager
        manager = nil
        XCTAssertNil(releasedManager)
        XCTAssertThrowsError(try XCTUnwrap(handle).offset())

        let reopened = BluetoothManager(commandWriter: { _ in }, scheduleRecovery: { _ in }, captureDirectory: directory)
        XCTAssertFalse(reopened.isCapturing)
        XCTAssertEqual(reopened.captureFileURL, url)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("TX: BEFORE_DEINIT\nsaved response\r>\n\n"))
    }
}
