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

    /// Pack current must be emitted standalone so the manager pairs it with the voltage
    /// read from DID 0x1E3B, instead of a fabricated 400 V nominal.
    func testVolkswagenMEBCurrentParsing() {
        // Single frame (07 = 7 data bytes): 62 1E 3D [A B C D]
        // (0*16777216 + 2*65536 + 73*256 + 240) = 131072 + 18688 + 240 = 150000 -> (150000 - 150000)/100 = 0.0 A
        let raw = "17FE007B 07 62 1E 3D 00 02 49 F0\r\n>"
        let update = profile.parseResponse(command: "03221E3D55555555", rawResponse: raw)

        guard case .packCurrent(let a)? = update else {
            XCTFail("Expected .packCurrent update, got \(String(describing: update))")
            return
        }
        XCTAssertEqual(a, 0.0, accuracy: 0.1)
    }

    func testVolkswagenMEBCurrentSignConvention() {
        // raw = 100000 -> (100000 - 150000)/100 * -1 = +500 A discharge is out of the
        // plausible window; use raw = 149000 -> (-1000)/100 * -1 = +10.0 A discharge.
        let raw = "17FE007B 07 62 1E 3D 00 02 46 08\r\n>"
        guard case .packCurrent(let a)? = profile.parseResponse(command: "03221E3D55555555", rawResponse: raw) else {
            return XCTFail("Expected .packCurrent update")
        }
        XCTAssertEqual(a, 10.0, accuracy: 0.1)
    }

    func testVolkswagenMEBVoltageParsing() {
        // Single frame (05 = 5 data bytes): 62 1E 3B [A B]
        // (5*256 + 220) = 1500 -> 1500 / 4 = 375.0 V
        let raw = "17FE007B 05 62 1E 3B 05 DC\r\n>"
        let update = profile.parseResponse(command: "03221E3B55555555", rawResponse: raw)

        guard case .packVoltage(let v)? = update else {
            XCTFail("Expected .packVoltage update, got \(String(describing: update))")
            return
        }
        XCTAssertEqual(v, 375.0, accuracy: 0.1)
    }

    func testVolkswagenMEBSOCParsing() {
        // Single frame (04 = 4 data bytes): 62 02 8C [A]
        // If A = 200: (1.12 * 200 / 2.5) - 7.16 = 89.6 - 7.16 = 82.44%
        let raw = "17FE007B 04 62 02 8C C8\r\n>"
        let update = profile.parseResponse(command: "0322028C55555555", rawResponse: raw)
        
        guard case .soc(let val)? = update else {
            XCTFail("Expected .soc update, got \(String(describing: update))")
            return
        }
        XCTAssertEqual(val, 82.44, accuracy: 0.1)
    }

    /// DID 0x7448 is a status bitfield, not a power reading — it must report an unknown
    /// rate while charging rather than a fabricated 50 kW that would inflate kWh totals.
    func testVolkswagenMEBChargingStatusParsing() {
        // Bit 2 set (0x04) -> charging
        let rawCharging = "17FE007B 04 62 74 48 04\r\n>"
        let updateCharging = profile.parseResponse(command: "0322744855555555", rawResponse: rawCharging)
        guard case .chargingStats(let kw, let acOrDc)? = updateCharging else {
            XCTFail("Expected .chargingStats update, got \(String(describing: updateCharging))")
            return
        }
        XCTAssertNil(kw)
        XCTAssertEqual(acOrDc, "AC")

        // Bit 2 + Bit 1 set (0x06) -> DCFC
        let rawDCFC = "17FE007B 04 62 74 48 06\r\n>"
        let updateDCFC = profile.parseResponse(command: "0322744855555555", rawResponse: rawDCFC)
        guard case .chargingStats(let kwDC, let acOrDcDC)? = updateDCFC else {
            XCTFail("Expected .chargingStats update, got \(String(describing: updateDCFC))")
            return
        }
        XCTAssertNil(kwDC)
        XCTAssertEqual(acOrDcDC, "DC")

        // Not charging -> an explicit zero rate.
        let rawIdle = "17FE007B 04 62 74 48 00\r\n>"
        guard case .chargingStats(let kwIdle, _)? = profile.parseResponse(command: "0322744855555555", rawResponse: rawIdle) else {
            return XCTFail("Expected .chargingStats update")
        }
        XCTAssertEqual(kwIdle, 0.0)
    }

    /// Multi-frame replies must be reassembled before positional byte extraction —
    /// otherwise the CAN ID and consecutive-frame PCI byte land inside the payload.
    func testVolkswagenMEBCurrentParsesFromMultiFrameReply() {
        let raw = """
        17FE007B 10 07 62 1E 3D 00 02\r
        17FE007B 21 49 F0 55 55 55 55 55\r
        >
        """
        guard case .packCurrent(let a)? = profile.parseResponse(command: "03221E3D55555555", rawResponse: raw) else {
            return XCTFail("Expected .packCurrent update")
        }
        XCTAssertEqual(a, 0.0, accuracy: 0.1)
    }
}
