import XCTest
@testable import VoltLinkEngine

final class GenericOBD2ProfileTests: XCTestCase {

    func testEngineLoadParsing() {
        let profile = GenericOBD2Profile()
        // 0xFF -> 100%
        let raw = "7E8 03 41 04 FF\r\n>"
        let update = profile.parseResponse(command: "0104", rawResponse: raw)
        if case .engineLoad(let pct) = update {
            XCTAssertEqual(pct, 100.0, accuracy: 0.1)
        } else {
            XCTFail("Expected engineLoad update")
        }
    }

    func testCoolantTempParsing() {
        let profile = GenericOBD2Profile()
        // 0x50 (80) - 40 = 40C
        let raw = "7E8 03 41 05 50\r\n>"
        let update = profile.parseResponse(command: "0105", rawResponse: raw)
        if case .coolantTemp(let c) = update {
            XCTAssertEqual(c, 40.0, accuracy: 0.1)
        } else {
            XCTFail("Expected coolantTemp update")
        }
    }

    func testThrottlePositionParsing() {
        let profile = GenericOBD2Profile()
        // 0x80 (128) -> ~50.2%
        let raw = "7E8 03 41 11 80\r\n>"
        let update = profile.parseResponse(command: "0111", rawResponse: raw)
        if case .throttlePosition(let pct) = update {
            XCTAssertEqual(pct, 50.2, accuracy: 0.5)
        } else {
            XCTFail("Expected throttlePosition update")
        }
    }

    func testFuelLevelParsing() {
        let profile = GenericOBD2Profile()
        let raw = "7E8 03 41 2F 80\r\n>"
        let update = profile.parseResponse(command: "012F", rawResponse: raw)
        if case .fuelLevel(let pct) = update {
            XCTAssertEqual(pct, 50.2, accuracy: 0.5)
        } else {
            XCTFail("Expected fuelLevel update")
        }
    }

    func testIntakeAirTempParsing() {
        let profile = GenericOBD2Profile()
        let raw = "7E8 03 41 0F 28\r\n>"
        let update = profile.parseResponse(command: "010F", rawResponse: raw)
        if case .intakeAirTemp(let c) = update {
            XCTAssertEqual(c, 0.0, accuracy: 0.1)
        } else {
            XCTFail("Expected intakeAirTemp update")
        }
    }

    func testSupportedMetricsExcludesUnimplementedTorque() {
        let profile = GenericOBD2Profile()
        XCTAssertFalse(profile.supportedMetrics.contains(.motorTorque))
        XCTAssertTrue(profile.supportedMetrics.contains(.engineLoad))
    }
}
