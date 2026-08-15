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

    func testMercedesEQA250PowerParsingMultiFrame() {
        let profile = MercedesEQA250Profile()
        let rawResponse = "7E8 10 0A 62 01 05 0E 74 03\r\n7E8 21 E8 00 00 00 00 00 00\r\n>"
        let update = profile.parseResponse(command: "220105", rawResponse: rawResponse)

        if case .power(let v, let a, let kw) = update {
            XCTAssertEqual(v, 370.0, accuracy: 0.1)
            XCTAssertEqual(a, 100.0, accuracy: 0.1)
            XCTAssertEqual(kw, 37.0, accuracy: 0.1)
        } else {
            XCTFail("Expected Power update from reassembled multi-frame payload")
        }
    }

    func testMercedesEQA250SOCParsing() {
        let profile = MercedesEQA250Profile()
        // Response format: 62 01 01 9C (9C hex = 156 dec -> 156 * 0.5 = 78%)
        let rawResponse = "7E8 04 62 01 01 9C\r\n>"
        let update = profile.parseResponse(command: "220101", rawResponse: rawResponse)
        
        if case .soc(let percentage) = update {
            XCTAssertEqual(percentage, 78.0, accuracy: 0.1)
        } else {
            XCTFail("Expected SOC update")
        }
    }

    func testMercedesEQA250PowerParsing() {
        let profile = MercedesEQA250Profile()
        // Voltage: 370.0V (3700 = 0x0E74), Current: 100.0A (1000 = 0x03E8) -> 37.0 kW
        let rawResponse = "7E8 07 62 01 05 0E 74 03 E8\r\n>"
        let update = profile.parseResponse(command: "220105", rawResponse: rawResponse)

        if case .power(let v, let a, let kw) = update {
            XCTAssertEqual(v, 370.0, accuracy: 0.1)
            XCTAssertEqual(a, 100.0, accuracy: 0.1)
            XCTAssertEqual(kw, 37.0, accuracy: 0.1)
        } else {
            XCTFail("Expected Power update")
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
