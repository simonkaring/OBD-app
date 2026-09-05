import XCTest
@testable import VoltLinkEngine

/// Records every command written and replies with one canned response.
private final class ScriptedConnection: OBDConnectionProtocol {
    var state: BLEConnectionState = .ready(deviceName: "Scripted")
    weak var delegate: OBDConnectionDelegate?
    private(set) var sentCommands: [String] = []
    private let response: Result<String, Error>

    init(response: Result<String, Error>) {
        self.response = response
    }

    func connect(peripheralName: String?) {}
    func disconnect() {}

    func sendCommand(_ command: String, completion: ((Result<String, Error>) -> Void)?) {
        sentCommands.append(command)
        completion?(response)
    }
}

final class OBDParserTests: XCTestCase {
    
    func testISO15765ParserSingleFrame() {
        let parser = ISO15765Parser()
        let raw = "7E8 03 41 0D 32\r\n>"
        let payload = parser.assembleISOTPPayload(raw)
        XCTAssertEqual(payload, "410D32")
    }

    func testISO15765ParserMultiFrame() {
        let parser = ISO15765Parser()
        // First Frame (10 0A = 10 total data bytes) + Consecutive Frame (21 = sequence 1),
        // spaces on (AT S1). The CF's trailing 00 padding is beyond the declared length
        // and must be dropped, otherwise byte offsets past the message read as zeros.
        let raw = "7E8 10 0A 62 01 05 0E 74 03\r\n7E8 21 E8 00 00 00 00 00 00\r\n>"
        let payload = parser.assembleISOTPPayload(raw)
        XCTAssertEqual(payload, "6201050E7403E8000000")
    }

    func testISO15765ParserDiscardsFlowControlFrames() {
        let parser = ISO15765Parser()
        // The adapter echoes back the flow-control frame it sent (30 00 00) between
        // the first and consecutive frames; it carries no payload.
        let raw = "7E8 10 0A 62 01 05 0E 74 03\r\n7E0 30 00 00 00 00 00 00 00\r\n7E8 21 E8 00 00 00 00 00 00\r\n>"
        let payload = parser.assembleISOTPPayload(raw)
        XCTAssertEqual(payload, "6201050E7403E8000000")
    }

    func testISO15765ParserSkipsNonHexAdapterChatter() {
        let parser = ISO15765Parser()
        let raw = "NO DATA\r\n7E8 03 41 0D 32\r\nCAN ERROR\r\n>"
        let payload = parser.assembleISOTPPayload(raw)
        XCTAssertEqual(payload, "410D32")
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

    /// `assembleISOTPPayload` has no CAN-ID demux — it dispatches purely on the ISO-TP PCI
    /// nibble and concatenates every line's data bytes into one buffer regardless of which
    /// ECU sent it. Documents the current (naive) behavior for a broadcast reply where two
    /// ECUs (7E8, 7E9) each answer with their own single frame: the two payloads are flattened
    /// back-to-back rather than kept separate. (A caller like `DTCScannerService` that scans
    /// for a service byte from the front would only ever see the first ECU's reply.)
    /// Two ECUs replying to the same broadcast are demuxed into separate per-ECU payloads
    /// instead of being flattened into one buffer.
    func testISO15765ParserDemuxesMultiECUBroadcastReplies() {
        let parser = ISO15765Parser()
        // 7E8 replies "43 00" (service 0x43, count 0 = no stored codes).
        // 7E9 replies "43 01 0A 80" (service 0x43, count 1, DTC 0A80).
        let raw = "7E8 02 43 00\r\n7E9 04 43 01 0A 80\r\n>"
        let results = parser.assembleISOTPPayloads(raw)
        XCTAssertEqual(results.map(\.ecu), ["7E8", "7E9"])
        XCTAssertEqual(results.map(\.payload), ["4300", "43010A80"])
    }

    func testDTCScannerMergesCodesFromAllRespondingECUs() {
        let scanner = DTCScannerService()
        // 7E8 replies "no codes"; 7E9 reports DTC 0A80 — the merge must not let 7E8's
        // empty reply hide 7E9's code.
        let raw = "7E8 02 43 00\r\n7E9 04 43 01 0A 80\r\n>"
        let codes = scanner.parseDTCResponse(raw, serviceByte: 0x43)
        XCTAssertEqual(codes.map(\.code), ["P0A80"])
    }

    /// A Consecutive Frame arriving with the wrong sequence nibble now invalidates that
    /// ECU's bucket entirely, rather than silently corrupting the assembled payload.
    func testISO15765ParserDropsMessageWithOutOfOrderConsecutiveFrame() {
        let parser = ISO15765Parser()
        // First Frame declares 10 total bytes. The real CF (seq 1, "E8 00...") is preceded
        // by a bogus CF claiming to be seq 2 ("FF FF...") — out of order on the wire.
        let raw = "7E8 10 0A 62 01 05 0E 74 03\r\n7E8 22 FF FF FF FF FF FF\r\n7E8 21 E8 00 00 00 00 00 00\r\n>"
        XCTAssertEqual(parser.assembleISOTPPayload(raw), "")
        XCTAssertEqual(parser.assembleISOTPPayloads(raw).count, 0)
    }

    /// Two ECUs interleaving First Frame + Consecutive Frame sequences must not clobber
    /// each other's multi-frame reassembly context.
    func testISO15765ParserKeepsSeparateMultiFrameContextsPerECU() {
        let parser = ISO15765Parser()
        let raw = """
        7E8 10 0A 62 01 05 0E 74 03\r
        7E9 10 09 62 01 0A 0D 3E 00\r
        7E8 21 E8 00 00 00 00 00 00\r
        7E9 21 11 22 33\r
        >
        """
        let results = parser.assembleISOTPPayloads(raw)
        let byECU = Dictionary(uniqueKeysWithValues: results.map { ($0.ecu, $0.payload) })
        XCTAssertEqual(byECU["7E8"], "6201050E7403E8000000")
        XCTAssertEqual(byECU["7E9"], "62010A0D3E00112233")
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

    func testMercedesEQA250IgnoresUnverifiedInverterSOC() {
        let profile = MercedesEQA250Profile()
        // DID 012F is an internal SOC-like value, not yet verified against customer SOC.
        let rawResponse = "18 DA F1 29 05 62 01 2F 01 6F\r\n>"
        let update = profile.parseResponse(command: "22012F", rawResponse: rawResponse)
        XCTAssertNil(update)
    }

    func testMercedesEQA250CustomerSOCParsing() {
        let profile = MercedesEQA250Profile()
        // Raw 0x3990 / 250 = 58.944% gross -> maps to 44.0% usable customer SoC
        let rawResponse = "18 DA F1 59 10 0B 62 02 10 04 00 00\r\n18 DA F1 59 21 39 90 00 00 00 AA AA\r\n>"
        let update = profile.parseResponse(command: "220210", rawResponse: rawResponse)

        if case .soc(let soc) = update {
            XCTAssertEqual(soc, 44.02, accuracy: 0.1)
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

    /// `parseResponses` has no override for `MercedesEQA250Profile`, so it must fall back to
    /// the protocol extension's default: wrap `parseResponse`'s single result in a one-element
    /// array (or an empty array on nil).
    func testParseResponsesDefaultWrapsSingleUpdate() {
        let profile = MercedesEQA250Profile()
        let rawResponse = "18 DA F1 59 05 62 01 0A 0D 3E\r\n>"
        let updates = profile.parseResponses(command: "22010A", rawResponse: rawResponse)

        XCTAssertEqual(updates.count, 1)
        if case .packVoltage(let voltage) = updates.first {
            XCTAssertEqual(voltage, 339.0, accuracy: 0.1)
        } else {
            XCTFail("Expected a single packVoltage update")
        }
    }

    func testMercedesEQA250PackCurrentParsing() {
        let profile = MercedesEQA250Profile()
        let rawResponse = "18 DA F1 59 05 62 01 0B FF 9C\r\n>"

        guard case .packCurrent(let current)? = profile.parseResponse(command: "22010B", rawResponse: rawResponse) else {
            return XCTFail("Expected pack current update")
        }
        XCTAssertEqual(current, -10.0, accuracy: 0.01)
    }

    func testMercedesEQA250BatteryTemperatureParsing() {
        let profile = MercedesEQA250Profile()
        let rawResponse = "18 DA F1 59 04 62 01 0C 41\r\n>"

        guard case .batteryTemp(let min, let max, let average)? = profile.parseResponse(command: "22010C", rawResponse: rawResponse) else {
            return XCTFail("Expected battery temperature update")
        }
        XCTAssertEqual(min, 25.0, accuracy: 0.01)
        XCTAssertEqual(max, 25.0, accuracy: 0.01)
        XCTAssertEqual(average, 25.0, accuracy: 0.01)
    }

    func testHyundaiKiaEGMPParsesPublicPackPowerFormula() {
        let profile = HyundaiKiaEGMPProfile()
        // Payload bytes K/L = 0xFF9C (-10.0 A), N/O = 0x0E74 (370.0 V).
        let rawResponse = "62 01 01 00 00 00 00 00 00 00 00 00 00 FF 9C 00 0E 74\r\n>"
        let update = profile.parseResponse(command: "220101", rawResponse: rawResponse)

        if case .power(let voltage, let current, let powerKW) = update {
            XCTAssertEqual(voltage, 370.0, accuracy: 0.01)
            XCTAssertEqual(current, -10.0, accuracy: 0.01)
            XCTAssertEqual(powerKW, -3.7, accuracy: 0.01)
        } else {
            XCTFail("Expected public Hyundai/Kia pack-power update")
        }
    }

    /// `220105`'s SOC branch (`ag/2` in the ABRP source) was previously untested — only the
    /// `220101` power branch had coverage.
    func testHyundaiKiaEGMPParsesSOCFrom220105() {
        let profile = HyundaiKiaEGMPProfile()
        var bytes = [String](repeating: "00", count: 40)
        bytes[32] = "64" // 100 -> /2 = 50.0%
        let raw = "62 01 05 " + bytes.joined(separator: " ") + "\r\n>"

        guard case .soc(let pct)? = profile.parseResponse(command: "220105", rawResponse: raw) else {
            return XCTFail("Expected SOC update from 220105")
        }
        XCTAssertEqual(pct, 50.0, accuracy: 0.01)
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

    /// The raw Mode 04 reply carries the `>` prompt and CAN header, so the odd-length hex
    /// string decoded to zero bytes and success was never detected.
    func testClearDTCsDetectsPositiveResponseInRawAdapterText() {
        let scanner = DTCScannerService()
        let connection = ScriptedConnection(response: .success("7E8 01 44\r\n>"))
        var result: Bool?
        scanner.clearDTCs(connection: connection) { result = $0 }
        XCTAssertEqual(result, true)
        XCTAssertEqual(connection.sentCommands, ["04"])
    }

    func testClearDTCsReportsFailureOnNegativeResponse() {
        let scanner = DTCScannerService()
        var result: Bool?
        scanner.clearDTCs(connection: ScriptedConnection(response: .success("7F 04 12\r\n>"))) { result = $0 }
        XCTAssertEqual(result, false)

        scanner.clearDTCs(connection: ScriptedConnection(response: .success("NO DATA\r\n>"))) { result = $0 }
        XCTAssertEqual(result, false)
    }

    /// Mode 03/07 need broadcast addressing, so the profile's receive filter must be
    /// cleared first and its addressing restored afterwards.
    func testScanClearsReceiveFilterAndRestoresProfileAddressing() {
        let scanner = DTCScannerService()
        let connection = ScriptedConnection(response: .success("43 00 00 00 00 00\r\n>"))
        scanner.scanDTCs(connection: connection, isDemo: false, restoreCommands: ["ATCRA 18DAF159", "AT SH 18DA59F1"])

        XCTAssertEqual(connection.sentCommands.prefix(3).map { $0 }, ["AT CRA", "AT SH 7DF", "03"])
        XCTAssertEqual(connection.sentCommands.suffix(2).map { $0 }, ["ATCRA 18DAF159", "AT SH 18DA59F1"])
    }

    func testDTCScannerModePendingCodes() {
        let scanner = DTCScannerService()
        let raw = "47 01 0A 80\r\n>"
        let codes = scanner.parseDTCResponse(raw, serviceByte: 0x47)
        XCTAssertEqual(codes.map(\.code), ["P0A80"])
    }

    // MARK: - ABRP community profiles

    /// Pack current must be emitted standalone so the manager multiplies it by the
    /// real measured pack voltage, not a hardcoded 400 V nominal.
    func testABRPCurrentUsesMeasuredVoltageNotNominal() throws {
        let machE = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "ford_MachE.json"))
        // ((signed(A)*256)+B)*0.1 over FF 9C = -10.0 A
        let update = machE.parseResponse(command: "2248F9", rawResponse: "7E8 05 62 48 F9 FF 9C\r\n>")
        guard case .packCurrent(let amps)? = update else {
            return XCTFail("expected .packCurrent, got \(String(describing: update))")
        }
        XCTAssertEqual(amps, -10.0, accuracy: 0.01)
    }

    /// `supportedMetrics` advertised SOH but `parseResponse` never emitted it.
    func testABRPEmitsStateOfHealth() throws {
        let machE = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "ford_MachE.json"))
        let update = machE.parseResponse(command: "22490C", rawResponse: "7E8 04 62 49 0C C8\r\n>")
        guard case .soh(let pct)? = update else {
            return XCTFail("expected .soh, got \(String(describing: update))")
        }
        XCTAssertEqual(pct, 100.0, accuracy: 0.01)
    }

    /// `INT16(A:B)*0.1` is not valid NSExpression syntax — it must be rejected, not
    /// handed to `NSExpression(format:)` where it raises an uncatchable ObjC exception.
    func testABRPRejectsNonArithmeticEquationInsteadOfCrashing() throws {
        let mini = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "Mini_MiniCooperSE.json"))
        XCTAssertNil(mini.parseResponse(command: "22DDBC", rawResponse: "607 05 62 DD BC 02 EE\r\n>"))
    }

    /// Substring matching cross-assigned metrics between DIDs sharing a prefix.
    func testABRPDoesNotCrossAssignMetricsBetweenSimilarDIDs() throws {
        let machE = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "ford_MachE.json"))
        // 2248F9 is current; 224845 is SOC. Neither response may decode as the other.
        if case .soc? = machE.parseResponse(command: "2248F9", rawResponse: "7E8 05 62 48 F9 FF 9C\r\n>") {
            XCTFail("current response decoded as SOC")
        }
        guard case .soc(let pct)? = machE.parseResponse(command: "224845", rawResponse: "7E8 04 62 48 45 64\r\n>") else {
            return XCTFail("224845 should decode as SOC")
        }
        XCTAssertEqual(pct, 50.0, accuracy: 0.01)
    }

    // MARK: - Nissan Leaf ZE1 (OVMS-derived, request/response PIDs only)

    func testNissanLeafZE1SOCParsing() {
        let profile = NissanLeafZE1Profile()
        // Group 0x01 reply: byte31/32/33 = 0B 35 24 -> raw 734500 / 10000 = 73.45%
        let rawResponse = "61 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 0B 35 24\r\n>"
        guard case .soc(let pct)? = profile.parseResponse(command: "2101", rawResponse: rawResponse) else {
            return XCTFail("Expected SOC update")
        }
        XCTAssertEqual(pct, 73.45, accuracy: 0.01)
    }

    func testNissanLeafZE1SOHParsing() {
        let profile = NissanLeafZE1Profile()
        // Group 0x61 reply: byte2/3 = 26 7A -> raw 9850 / 100 = 98.5%
        let rawResponse = "61 61 00 00 26 7A\r\n>"
        guard case .soh(let pct)? = profile.parseResponse(command: "2161", rawResponse: rawResponse) else {
            return XCTFail("Expected SOH update")
        }
        XCTAssertEqual(pct, 98.5, accuracy: 0.01)
    }

    // MARK: - BYD Atto 3 (OVMS-derived, ABRP JSON)

    func testBYDAtto3SOCAndVoltageParsing() throws {
        let bydAtto3 = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "byd_atto3.json"))
        guard case .soc(let pct)? = bydAtto3.parseResponse(command: "220005", rawResponse: "7EF 04 62 00 05 46\r\n>") else {
            return XCTFail("Expected SOC update")
        }
        XCTAssertEqual(pct, 70.0, accuracy: 0.01)

        // Bytes 0F A0 = 4000 -> /10 = 400.0V
        guard case .packVoltage(let volts)? = bydAtto3.parseResponse(command: "220008", rawResponse: "7EF 05 62 00 08 0F A0\r\n>") else {
            return XCTFail("Expected packVoltage update")
        }
        XCTAssertEqual(volts, 400.0, accuracy: 0.01)
    }

    /// Every profile the catalog points at must resolve, and the zero-capacity
    /// sanity filter must not swallow the ICE entry.
    func testCatalogProfilesAllResolve() {
        let models = VehicleCatalog.allModels
        XCTAssertFalse(models.isEmpty)
        for model in models {
            let profile = model.profileID.makeProfile()
            XCTAssertFalse(profile.pollingCommands.isEmpty, "\(model.fullName) has no polling commands")
            if model.telemetrySupport != .generic {
                // A missing/undecodable ABRP JSON silently falls back to the generic
                // profile, which would leave the car advertising telemetry it can't read.
                XCTAssertNotEqual(profile.vehicleName, GenericEVProfile().vehicleName,
                                  "\(model.fullName) claims \(model.telemetrySupport) support but fell back to the generic profile")
            }
        }
        XCTAssertTrue(models.contains { $0.powertrain == .ice }, "ICE entry was filtered out by the capacity check")
    }
}
