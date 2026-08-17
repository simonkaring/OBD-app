import XCTest
@testable import VoltLinkEngine

final class VolkswagenMEBProfileTests: XCTestCase {
    private let profile = VolkswagenMEBProfile()

    func testVolkswagenMEBInitializationCommands() {
        XCTAssertTrue(profile.isElectricVehicle)
        XCTAssertEqual(profile.batteryUsableCapacityKWh, 77.0)
        XCTAssertTrue(profile.initializationCommands.contains("AT SP 7"))
        XCTAssertTrue(profile.initializationCommands.contains("AT SH FC007B"))
    }

    func testVolkswagenMEBCurrentParsing() {
        // Response with 62 1E 3D [A B C D]
        // Example raw: 04 62 1E 3D 00 02 49 F0
        // (0*16777216 + 2*65536 + 73*256 + 240) = 131072 + 18688 + 240 = 150000 -> (150000 - 150000)/100 = 0.0 A
        let raw = "04 62 1E 3D 00 02 49 F0"
        let update = profile.parseResponse(command: "03221E3D55555555", rawResponse: raw)
        
        guard case .power(let v, let a, let kw)? = update else {
            XCTFail("Expected .power update, got \(String(describing: update))")
            return
        }
        XCTAssertEqual(v, 400.0)
        XCTAssertEqual(a, 0.0, accuracy: 0.1)
        XCTAssertEqual(kw, 0.0, accuracy: 0.1)
    }

    func testVolkswagenMEBVoltageParsing() {
        // Response with 62 1E 3B [A B]
        // Example raw: 04 62 1E 3B 05 DC
        // (5*256 + 220) = 1500 -> 1500 / 4 = 375.0 V
        let raw = "04 62 1E 3B 05 DC"
        let update = profile.parseResponse(command: "03221E3B55555555", rawResponse: raw)
        
        guard case .packVoltage(let v)? = update else {
            XCTFail("Expected .packVoltage update, got \(String(describing: update))")
            return
        }
        XCTAssertEqual(v, 375.0, accuracy: 0.1)
    }

    func testVolkswagenMEBSOCParsing() {
        // Response with 62 02 8C [A]
        // If A = 200: (1.12 * 200 / 2.5) - 7.16 = 89.6 - 7.16 = 82.44%
        let raw = "03 62 02 8C C8"
        let update = profile.parseResponse(command: "0322028C55555555", rawResponse: raw)
        
        guard case .soc(let val)? = update else {
            XCTFail("Expected .soc update, got \(String(describing: update))")
            return
        }
        XCTAssertEqual(val, 82.44, accuracy: 0.1)
    }

    func testVolkswagenMEBChargingStatusParsing() {
        // Bit 2 set (0x04) -> charging
        let rawCharging = "03 62 74 48 04"
        let updateCharging = profile.parseResponse(command: "0322744855555555", rawResponse: rawCharging)
        guard case .chargingStats(let kw, let acOrDc)? = updateCharging else {
            XCTFail("Expected .chargingStats update, got \(String(describing: updateCharging))")
            return
        }
        XCTAssertEqual(kw, 50.0)
        XCTAssertEqual(acOrDc, "AC")

        // Bit 2 + Bit 1 set (0x06) -> DCFC
        let rawDCFC = "03 62 74 48 06"
        let updateDCFC = profile.parseResponse(command: "0322744855555555", rawResponse: rawDCFC)
        guard case .chargingStats(let kwDC, let acOrDcDC)? = updateDCFC else {
            XCTFail("Expected .chargingStats update, got \(String(describing: updateDCFC))")
            return
        }
        XCTAssertEqual(kwDC, 50.0)
        XCTAssertEqual(acOrDcDC, "DC")
    }
}
