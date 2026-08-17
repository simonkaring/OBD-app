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
}
