import XCTest
import CoreBluetooth
@testable import VoltLinkEngine

final class BluetoothManagerTests: XCTestCase {

    func testBLEConstantsIncludesVLinkerAndIOSVlinkProfiles() {
        // Vgate vLinker & ios-vlink proprietary 128-bit profile
        XCTAssertTrue(BLEConstants.allSupportedServices.contains(BLEConstants.vgate128ServiceUUID))
        XCTAssertTrue(BLEConstants.knownWriteCharacteristics.contains(BLEConstants.vgate128CharUUID))
        XCTAssertTrue(BLEConstants.knownNotifyCharacteristics.contains(BLEConstants.vgate128CharUUID))

        // HM-10 / CC2541 profile
        XCTAssertTrue(BLEConstants.allSupportedServices.contains(BLEConstants.hm10ServiceUUID))
        XCTAssertTrue(BLEConstants.allSupportedServices.contains(BLEConstants.hm10LongServiceUUID))
        XCTAssertTrue(BLEConstants.knownWriteCharacteristics.contains(BLEConstants.hm10CharUUID))
        XCTAssertTrue(BLEConstants.knownNotifyCharacteristics.contains(BLEConstants.hm10CharUUID))

        // Nordic UART Service (NUS)
        XCTAssertTrue(BLEConstants.allSupportedServices.contains(BLEConstants.nordicUARTService))
        XCTAssertTrue(BLEConstants.knownWriteCharacteristics.contains(BLEConstants.nordicUARTWrite))
        XCTAssertTrue(BLEConstants.knownNotifyCharacteristics.contains(BLEConstants.nordicUARTNotify))

        // Standard 18F0 & FFF0 profiles
        XCTAssertTrue(BLEConstants.allSupportedServices.contains(BLEConstants.vgateServiceUUID))
        XCTAssertTrue(BLEConstants.allSupportedServices.contains(BLEConstants.vgateShortServiceUUID))
        XCTAssertTrue(BLEConstants.allSupportedServices.contains(BLEConstants.genericUARTService))
    }

    func testBLEConstantsIgnoredStandardServices() {
        // Ensure standard SIG informational services are ignored during candidate UART selection
        XCTAssertTrue(BLEConstants.ignoredStandardServices.contains(CBUUID(string: "1800")))
        XCTAssertTrue(BLEConstants.ignoredStandardServices.contains(CBUUID(string: "1801")))
        XCTAssertTrue(BLEConstants.ignoredStandardServices.contains(CBUUID(string: "180A")))
        XCTAssertTrue(BLEConstants.ignoredStandardServices.contains(CBUUID(string: "180F")))
    }

    func testBLEConnectionStateEquatabilityAndIsConnected() {
        XCTAssertFalse(BLEConnectionState.disconnected.isConnected)
        XCTAssertFalse(BLEConnectionState.scanning.isConnected)
        XCTAssertFalse(BLEConnectionState.connecting(deviceName: "ios-vlink").isConnected)
        XCTAssertFalse(BLEConnectionState.error("Timeout").isConnected)

        XCTAssertTrue(BLEConnectionState.ready(deviceName: "ios-vlink").isConnected)
        XCTAssertTrue(BLEConnectionState.demoMode.isConnected)

        XCTAssertEqual(
            BLEConnectionState.connecting(deviceName: "ios-vlink"),
            BLEConnectionState.connecting(deviceName: "ios-vlink")
        )
        XCTAssertNotEqual(
            BLEConnectionState.connecting(deviceName: "ios-vlink"),
            BLEConnectionState.connecting(deviceName: "other-adapter")
        )
    }

    func testBluetoothManagerInitialState() {
        let manager = BluetoothManager()
        XCTAssertEqual(manager.state, .disconnected)
        XCTAssertTrue(manager.discoveredDevices.isEmpty)
        XCTAssertTrue(manager.log.isEmpty)
    }

    @MainActor
    func testTimeoutGatesCommandsQueuedByCompletionAndDuringRecovery() throws {
        var writes: [String] = []
        var recoveries: [DispatchWorkItem] = []
        let manager = BluetoothManager(
            commandWriter: { writes.append(String(decoding: $0, as: UTF8.self)) },
            scheduleRecovery: { recoveries.append($0) }
        )
        var secondResult: Result<String, Error>?
        manager.sendCommand("22010A") { result in
            if case .success = result { XCTFail("Expected a timeout") }
            manager.sendCommand("220210") { secondResult = $0 }
        }
        manager.completeInFlight(.failure(NSError(domain: "BluetoothManager", code: -2)), rawResponse: nil)
        manager.sendCommand("AT RV", completion: nil)

        XCTAssertEqual(writes, ["22010A\r"])
        XCTAssertNil(secondResult)
        let recovery = try XCTUnwrap(recoveries.first)
        manager.receiveResponseChunk("late response\r>")
        manager.receiveResponseChunk("late partial response")
        recovery.perform()
        XCTAssertEqual(writes, ["22010A\r", "220210\r"])

        manager.receiveResponseChunk("62 02 10")
        recovery.perform()
        manager.receiveResponseChunk(" 04 00 00 40 F4\r>")
        XCTAssertEqual(try XCTUnwrap(secondResult).get(), "62 02 10 04 00 00 40 F4\r>")
        XCTAssertEqual(writes, ["22010A\r", "220210\r", "AT RV\r"])
        manager.disconnect()
    }

    @MainActor
    func testOldRecoveryCannotReleaseALaterDrain() throws {
        var writes: [String] = []
        var recoveries: [DispatchWorkItem] = []
        let manager = BluetoothManager(
            commandWriter: { writes.append(String(decoding: $0, as: UTF8.self)) },
            scheduleRecovery: { recoveries.append($0) }
        )
        manager.sendCommand("22010A", completion: nil)
        manager.sendCommand("220210", completion: nil)
        manager.sendCommand("AT RV", completion: nil)
        let timeout = NSError(domain: "BluetoothManager", code: -2)
        manager.completeInFlight(.failure(timeout), rawResponse: nil)
        let firstRecovery = try XCTUnwrap(recoveries.first)
        firstRecovery.perform()
        manager.completeInFlight(.failure(timeout), rawResponse: nil)
        XCTAssertEqual(recoveries.count, 2)

        firstRecovery.perform()
        XCTAssertEqual(writes, ["22010A\r", "220210\r"])
        recoveries.last?.perform()
        XCTAssertEqual(writes, ["22010A\r", "220210\r", "AT RV\r"])
        manager.disconnect()
    }

    @MainActor
    func testDisconnectFromTimeoutCompletionCancelsRecoveryAndFailsQueuedCommandOnce() throws {
        var writes: [String] = []
        var recoveries: [DispatchWorkItem] = []
        let manager = BluetoothManager(
            commandWriter: { writes.append(String(decoding: $0, as: UTF8.self)) },
            scheduleRecovery: { recoveries.append($0) }
        )
        var queuedCompletions = 0
        manager.sendCommand("22010A") { _ in manager.disconnect() }
        manager.sendCommand("220210") { result in
            queuedCompletions += 1
            if case .success = result { XCTFail("Expected disconnect failure") }
            manager.sendCommand("AT RV") { result in
                if case .success = result { XCTFail("Must not send while disconnected") }
            }
        }

        manager.completeInFlight(.failure(NSError(domain: "BluetoothManager", code: -2)), rawResponse: nil)
        let recovery = try XCTUnwrap(recoveries.first)
        XCTAssertTrue(recovery.isCancelled)
        recovery.perform()
        XCTAssertEqual(manager.state, .disconnected)
        XCTAssertEqual(queuedCompletions, 1)
        XCTAssertEqual(writes, ["22010A\r"])
    }

    @MainActor
    func testResetCancelsRecoveryWithoutClearingTheNextCommandsBuffer() throws {
        var recoveries: [DispatchWorkItem] = []
        let manager = BluetoothManager(commandWriter: { _ in }, scheduleRecovery: { recoveries.append($0) })
        manager.sendCommand("22010A", completion: nil)
        manager.completeInFlight(.failure(NSError(domain: "BluetoothManager", code: -2)), rawResponse: nil)
        let recovery = try XCTUnwrap(recoveries.first)

        // Retain the injected writer to simulate transport reuse after connection reset.
        manager.resetConnectionState()
        XCTAssertTrue(recovery.isCancelled)
        var response: Result<String, Error>?
        manager.sendCommand("220210") { response = $0 }
        manager.receiveResponseChunk("62 02 10")
        recovery.perform()
        manager.receiveResponseChunk(" 04 00 00 40 F4\r>")
        XCTAssertEqual(try XCTUnwrap(response).get(), "62 02 10 04 00 00 40 F4\r>")
        manager.disconnect()
    }

    @MainActor
    func testScanningAndDisconnectStatesReachDelegate() {
        let manager = BluetoothManager(commandWriter: { _ in }, scheduleRecovery: { _ in })
        manager.disconnect()
        let delegate = ConnectionStateRecorder()
        manager.delegate = delegate

        manager.connect()
        XCTAssertEqual(manager.state, .scanning)
        manager.disconnect()
        XCTAssertEqual(delegate.states, [.scanning, .disconnected])
    }
}

private final class ConnectionStateRecorder: OBDConnectionDelegate {
    var states: [BLEConnectionState] = []

    func obdConnectionStateDidChange(_ state: BLEConnectionState) {
        states.append(state)
    }

    func obdConnectionDidReceiveResponse(command: String, rawResponse: String) {}
}
