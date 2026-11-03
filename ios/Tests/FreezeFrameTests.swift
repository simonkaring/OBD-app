import XCTest

@testable import VoltLinkEngine

final class FreezeFrameTests: XCTestCase {
    func testDecodesSpeedWithCANHeader() throws {
        let value = try XCTUnwrap(FreezeFrameSignal.speed.parse(rawResponse: "7E8 04 42 0D 00 3C\r\n>"))
        XCTAssertEqual(value, 60.0, accuracy: 0.001)
        XCTAssertEqual(FreezeFrameSignal.speed.display(value), "60 km/h")
    }

    func testDecodesRPMFromTwoBytes() throws {
        let value = try XCTUnwrap(FreezeFrameSignal.rpm.parse(rawResponse: "42 0C 00 1A F8"))
        XCTAssertEqual(value, 1726.0, accuracy: 0.001)
    }

    func testDecodesCoolantAndLoadWithStandardScaling() throws {
        XCTAssertEqual(try XCTUnwrap(FreezeFrameSignal.coolantTemp.parse(rawResponse: "42 05 00 64")), 60, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(FreezeFrameSignal.engineLoad.parse(rawResponse: "42 04 00 80")), 50.196, accuracy: 0.01)
    }

    func testDecodesControlModuleVoltage() throws {
        let value = try XCTUnwrap(FreezeFrameSignal.controlModuleVoltage.parse(rawResponse: "42 42 00 30 A8"))
        XCTAssertEqual(value, 12.456, accuracy: 0.001)
        let expected = 12.456.formatted(.number.precision(.fractionLength(1))) + " V"
        XCTAssertEqual(FreezeFrameSignal.controlModuleVoltage.display(value), expected)
    }

    func testIgnoresWrongFrameNumberAndNegativeResponses() {
        XCTAssertNil(FreezeFrameSignal.speed.parse(rawResponse: "42 0D 01 3C"))
        XCTAssertNil(FreezeFrameSignal.speed.parse(rawResponse: "NO DATA"))
        XCTAssertNil(FreezeFrameSignal.speed.parse(rawResponse: "7F 02 12"))
        XCTAssertNil(FreezeFrameSignal.rpm.parse(rawResponse: "42 0C 00 1A"))
    }

    func testAllCommandsUseMode02FrameZero() {
        for signal in FreezeFrameSignal.allCases {
            XCTAssertEqual(signal.command.count, 6)
            XCTAssertTrue(signal.command.hasPrefix("02"))
            XCTAssertTrue(signal.command.hasSuffix("00"))
        }
    }

    func testOrderedValuesFollowSignalOrderAndSkipMissingSignals() {
        let frames = [
            FreezeFrameSignal.speed.label: "42 km/h",
            FreezeFrameSignal.coolantTemp.label: "78 °C",
        ]
        let ordered = FreezeFrameSignal.orderedValues(from: frames)
        XCTAssertEqual(ordered.map(\.label), [FreezeFrameSignal.coolantTemp.label, FreezeFrameSignal.speed.label])
    }
}
