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

    func testHybridEVBatterySOCParsing() {
        let profile = GenericOBD2Profile()
        // 0x80 (128) -> ~50.2% (SAE J1979 PID 5B, works on any EV without manufacturer-specific PIDs)
        let raw = "7E8 03 41 5B 80\r\n>"
        let update = profile.parseResponse(command: "015B", rawResponse: raw)
        if case .soc(let pct) = update {
            XCTAssertEqual(pct, 50.2, accuracy: 0.5)
        } else {
            XCTFail("Expected soc update from PID 5B")
        }
    }

    /// Extracts the single numeric value out of whichever `TelemetryUpdate` case a Mode 01
    /// PID decodes to, so the table below can assert on one shared shape.
    private func numericValue(_ update: TelemetryUpdate?) -> Double? {
        switch update {
        case .speed(let v): return v
        case .motorStats(let rpm, _): return rpm
        case .aux12V(let v): return v
        case .ambientAirTemp(let v): return v
        case .maf(let v): return v
        case .manifoldPressure(let v): return v
        case .oilTemp(let v): return v
        case .timingAdvance(let v): return v
        case .barometricPressure(let v): return v
        default: return nil
        }
    }

    /// Table-driven coverage for every remaining `pollingCommands` entry not already covered
    /// by a dedicated test above (010D, 010C, 0142, 0146, 0110, 010B, 015C, 010E, 0133).
    func testGenericOBD2ProfileDecodesEveryRemainingPolledPID() {
        let profile = GenericOBD2Profile()
        let cases: [(command: String, raw: String, expected: Double)] = [
            ("010D", "7E8 03 41 0D 32\r\n>", 50.0),                  // Speed: 0x32 = 50 km/h
            ("010C", "7E8 04 41 0C 1A F8\r\n>", 1726.0),             // RPM: (0x1AF8)/4 = 1726
            ("0142", "7E8 04 41 42 30 D4\r\n>", 12.5),               // 12V: (0x30D4)/1000 = 12.5 V
            ("0146", "7E8 03 41 46 46\r\n>", 30.0),                  // Ambient: 0x46(70) - 40 = 30
            ("0110", "7E8 04 41 10 01 2C\r\n>", 3.0),                // MAF: (0x012C)/100 = 3.0 g/s
            ("010B", "7E8 03 41 0B 65\r\n>", 101.0),                 // MAP: 0x65 = 101 kPa
            ("015C", "7E8 03 41 5C 5A\r\n>", 50.0),                  // Oil temp: 0x5A(90) - 40 = 50
            ("010E", "7E8 03 41 0E 80\r\n>", 0.0),                   // Timing advance: 0x80/2 - 64 = 0
            ("0133", "7E8 03 41 33 64\r\n>", 100.0)                  // Barometric: 0x64 = 100 kPa
        ]

        for testCase in cases {
            let update = profile.parseResponse(command: testCase.command, rawResponse: testCase.raw)
            guard let value = numericValue(update) else {
                XCTFail("\(testCase.command) produced no decodable update: \(String(describing: update))")
                continue
            }
            XCTAssertEqual(value, testCase.expected, accuracy: 0.1,
                            "\(testCase.command) decoded to \(value), expected \(testCase.expected)")
        }
    }
}
