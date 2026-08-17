import XCTest
@testable import VoltLinkEngine

final class OBDParserTests: XCTestCase {
    
    func testISO15765ParserSingleFrame() {
        let parser = ISO15765Parser()
        let raw = "7E8 03 41 0D 32\r\n>"
        let payload = parser.assembleISOTPPayload(raw)
        XCTAssertEqual(payload, "410D32")
    }

    func testISO15765ParserMultiFrame() {
        let parser = ISO15765Parser()
        // First Frame (10 0A = length 10) + Consecutive Frame (21 = sequence 1), spaces on (AT S1)
        let raw = "7E8 10 0A 62 01 05 0E 74 03\r\n7E8 21 E8 00 00 00 00 00 00\r\n>"
        let payload = parser.assembleISOTPPayload(raw)
        XCTAssertEqual(payload, "6201050E7403E8000000000000")
    }

    func testISO15765ParserSingleFrameZeroLengthDoesNotCrash() {
        let parser = ISO15765Parser()
        // PCI byte 00 = single frame declaring zero data bytes; must not trap on an invalid slice range
        let raw = "7E8 00\r\n>"
        let payload = parser.assembleISOTPPayload(raw)
        XCTAssertEqual(payload, "")
    }

    func testISO15765Parser29BitHeaderSingleFrame() {
        let parser = ISO15765Parser()
        // Mercedes physical addressing: tester(F1) <- ECU(59), spaces on (AT S1)
        let raw = "18 DA F1 59 05 62 01 0A 0D 3E\r\n>"
        let payload = parser.assembleISOTPPayload(raw)
        XCTAssertEqual(payload, "62010A0D3E")
    }

    func testISO15765Parser29BitHeaderMultiFrame() {
        let parser = ISO15765Parser()
        let raw = "18 DA F1 59 10 0B 62 01 00 00 00\r\n18 DA F1 59 21 FF 00 02 FF FF AA\r\n>"
        let payload = parser.assembleISOTPPayload(raw)
        XCTAssertEqual(payload, "6201000000FF0002FFFFAA")
    }

    func testMercedesEQA250ForcesCANProtocolInsteadOfAutoDetect() {
        let profile = MercedesEQA250Profile()
        // Confirmed via direct BLE probing against a real EQA (scratch/bus_probe.swift):
        // the gateway uses 29-bit extended CAN addressing (AT SP 7), not 11-bit (AT SP 6)
        // or auto-detect (AT SP 0, which also races the app's 4s command timeout).
        XCTAssertTrue(profile.initializationCommands.contains("AT SP 7"))
        XCTAssertFalse(profile.initializationCommands.contains("AT SP 6"))
        XCTAssertFalse(profile.initializationCommands.contains("AT SP 0"))
    }

    func testMercedesEQA250SOCParsing() {
        let profile = MercedesEQA250Profile()
        // ECU 0x29, DID 012F. Bytes 01 6F = 0x016F = 367 dec -> 367 * 0.1 = 36.7%
        let rawResponse = "18 DA F1 29 05 62 01 2F 01 6F\r\n>"
        let update = profile.parseResponse(command: "22012F", rawResponse: rawResponse)

        if case .soc(let percentage) = update {
            XCTAssertEqual(percentage, 36.7, accuracy: 0.1)
        } else {
            XCTFail("Expected SOC update")
        }
    }

    func testMercedesEQA250PackVoltageParsing() {
        let profile = MercedesEQA250Profile()
        // ECU 0x59, DID 010A. Bytes 0D 3E = 0x0D3E = 3390 dec -> 3390 * 0.1 = 339.0V
        let rawResponse = "18 DA F1 59 05 62 01 0A 0D 3E\r\n>"
        let update = profile.parseResponse(command: "22010A", rawResponse: rawResponse)

        if case .packVoltage(let voltage) = update {
            XCTAssertEqual(voltage, 339.0, accuracy: 0.1)
        } else {
            XCTFail("Expected packVoltage update")
        }
    }

    func testDTCLookup() {
        let db = DTCLocalDatabase.shared
        let code = db.lookup(code: "P0A80")
        XCTAssertEqual(code.code, "P0A80")
        XCTAssertEqual(code.severity, .critical)
        XCTAssertTrue(code.title.contains("Replace Hybrid/EV Battery Pack"))
    }

    func testDTCScannerSingleFrameDecodesCorrectCode() {
        let scanner = DTCScannerService()
        // 43 (Mode 03 response) 01 (count = 1) 0A 80 (DTC bytes) 00 00 (padding)
        let raw = "43 01 0A 80 00 00\r\n>"
        let codes = scanner.parseDTCResponse(raw, serviceByte: 0x43)
        XCTAssertEqual(codes.map(\.code), ["P0A80"])
    }

    func testDTCScannerNoCodesReturnsEmpty() {
        let scanner = DTCScannerService()
        let raw = "43 00 00 00 00 00\r\n>"
        let codes = scanner.parseDTCResponse(raw, serviceByte: 0x43)
        XCTAssertTrue(codes.isEmpty)
    }

    func testDTCScannerMultiFrameDecodesAllCodes() {
        let scanner = DTCScannerService()
        // First Frame: 43 04 01 43 01 33  (service=43, count=4, DTC1=0143, DTC2 starts 01/33...)
        // Consecutive Frame continues the byte stream: 02 47 03 01 00 00 00
        let raw = "7E8 10 0E 43 04 01 43 01 33\r\n7E8 21 02 47 03 01 00 00 00\r\n>"
        let codes = scanner.parseDTCResponse(raw, serviceByte: 0x43)
        XCTAssertEqual(codes.count, 4)
        XCTAssertEqual(codes.map(\.code), ["P0143", "P0133", "P0247", "P0301"])
    }

    func testDTCScannerModePendingCodes() {
        let scanner = DTCScannerService()
        let raw = "47 01 0A 80\r\n>"
        let codes = scanner.parseDTCResponse(raw, serviceByte: 0x47)
        XCTAssertEqual(codes.map(\.code), ["P0A80"])
    }
}
