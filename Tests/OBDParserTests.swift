import XCTest
@testable import VoltLinkEngine

/// Records every command written and replies with one canned response.
private final class ScriptedConnection: OBDConnectionProtocol {
    var state: BLEConnectionState = .ready(deviceName: "Scripted")
    weak var delegate: OBDConnectionDelegate?
    private(set) var sentCommands: [String] = []
    private let response: Result<String, Error>
    var responses: [String: Result<String, Error>] = [:]
    var heldCommand: String?
    var heldCompletion: ((Result<String, Error>) -> Void)?

    init(response: Result<String, Error>) {
        self.response = response
    }

    func connect(peripheralName: String?) {}
    func disconnect() { state = .disconnected }

    func sendCommand(_ command: String, completion: ((Result<String, Error>) -> Void)?) {
        sentCommands.append(command)
        if command == heldCommand { heldCompletion = completion; return }
        if let result = responses[command] { completion?(result) }
        else if command == "AT Z" { completion?(.success("ELM327 v2.2\r\n>")) }
        else if command.hasPrefix("AT") { completion?(.success("OK\r\n>")) }
        else if command == "07" { completion?(.success("47 00\r\n>")) }
        else { completion?(response) }
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

    func testISO15765ParserRejectsIncompleteAndInvalidSingleFrames() {
        let parser = ISO15765Parser()
        for header in ["", "7E8 ", "18 DA F1 59 ", "18DAF159 "] {
            for frame in ["03 41 0D", "00 41 0D 32", "08 41 0D 32 00 00 00 00 00"] {
                XCTAssertTrue(parser.assembleISOTPPayloads(header + frame).isEmpty, header + frame)
            }
        }
        XCTAssertEqual(parser.assembleISOTPPayload("7E8 03 41 0D 32 AA AA AA AA"), "410D32")
    }

    func testISO15765ParserRejectsIncompleteAndInterruptedMultiFrames() {
        let parser = ISO15765Parser()
        let firstFrame = "7E8 10 0A 62 01 05 0E 74 03"
        for suffix in ["", "\r7E8 21 E8", "\r7E8 21", "\r7E8 03 41 0D 32",
                       "\r7E8 10 08 62 01 0A 00 00 00\r7E8 21 11 22",
                       "\r7E8 62 01 05 E8 00 00 00"] {
            XCTAssertTrue(parser.assembleISOTPPayloads(firstFrame + suffix).isEmpty, suffix)
        }
        for frame in ["7E8 10", "7E8 10 0A", "7E8 10 00 62", "7E8 10 01 62"] {
            XCTAssertTrue(parser.assembleISOTPPayloads(frame).isEmpty, frame)
        }
    }

    func testISO15765ParserRejectsOrphanAndExtraConsecutiveFrames() {
        let parser = ISO15765Parser()
        for raw in [
            "7E8 21 62 01 0A 0D 3E",
            "21 62 01 0A 0D 3E",
            "7E8 03 41 0D 32\r7E8 21 00",
            "7E8 10 08 62 01 0A 0D 3E 00\r7E8 21 00 00\r7E8 22 00",
            "7E8 10 0E 62 01 0A 0D 3E 00\r7E8 21 00 00 00 00 00 00 00\r7E8 21 00"
        ] {
            XCTAssertTrue(parser.assembleISOTPPayloads(raw).isEmpty, raw)
        }
    }

    func testISO15765ParserRejectsMalformedByteTokens() {
        let parser = ISO15765Parser()
        for token in ["GG", "F", "000", "100", "+1", "-1", "0x01"] {
            for raw in [
                "7E8 \(token) 41 0D 32",
                "7E8 03 41 0D \(token)",
                "7E8 03 41 0D 32 \(token)",
                "7E8 10 \(token) 62 01 0A 00 00 00",
                "7E8 10 08 62 01 0A \(token) 00 00\r7E8 21 11 22",
                "7E8 10 08 62 01 0A 00 00 00\r7E8 21 11 \(token)",
                "62 01 0A 0D \(token)"
            ] {
                XCTAssertTrue(parser.assembleISOTPPayloads(raw).isEmpty, raw)
            }
        }
    }

    func testISO15765ParserInvalidFramesDoNotDiscardOtherECUs() {
        let parser = ISO15765Parser()
        for invalid in ["7E8 03 41 0D", "7E8 10 0A 62 01 05 0E 74 03",
                        "7E8 21 00", "7E8 03 41 0D GG",
                        "7E8 10 08 62 01 0A 00 00 00\r7E8 22 11 22"] {
            let results = parser.assembleISOTPPayloads(invalid + "\r7E9 03 41 0D 32")
            XCTAssertEqual(results.map(\.ecu), ["7E9"], invalid)
            XCTAssertEqual(results.map(\.payload), ["410D32"], invalid)
        }
    }

    func testISO15765ParserCompletesMultipleMessagesForSameECU() {
        let parser = ISO15765Parser()
        let message = "7E8 10 08 62 01 0A 0D 3E 00\r7E8 21 11 22 AA AA AA AA AA"
        let raw = message + "\r7E8 03 41 0D 32\r" + message
        XCTAssertEqual(parser.assembleISOTPPayload(raw), "62010A0D3E001122410D3262010A0D3E001122")
    }

    func testISO15765ParserConsecutiveFrameSequenceWraps() {
        let parser = ISO15765Parser()
        // 6 FF bytes + 16 CFs of 7 bytes = 118 (0x76); sequence wraps from F to 0.
        var frames = ["7E8 10 76 62 01 0A 00 00 00"]
        for sequence in 1...16 {
            frames.append(String(format: "7E8 %02X 00 00 00 00 00 00 00", 0x20 | (sequence & 0x0F)))
        }
        XCTAssertEqual(parser.assembleISOTPPayload(frames.joined(separator: "\r")),
                       "62010A" + String(repeating: "00", count: 115))
    }

    func testISO15765ParserPreservesHeaderlessFormattedPayloadsAndGenericProfiles() {
        let parser = ISO15765Parser()
        let results = parser.assembleISOTPPayloads("62 01 0A 0D 3E\r>")
        XCTAssertEqual(results.map(\.ecu), [ISO15765Parser.headerlessECU])
        XCTAssertEqual(results.map(\.payload), ["62010A0D3E"])
        let profiles: [any VehicleProfile] = [GenericOBD2Profile(), GenericEVProfile()]
        for raw in ["41 0D 32\r>", "03 41 0D 32\r>", "7E8 03 41 0D 32\r>"] {
            for profile in profiles {
                guard case .speed(let speed)? = profile.parseResponse(command: "010D", rawResponse: raw) else {
                    XCTFail("Expected generic speed update from \(raw)")
                    continue
                }
                XCTAssertEqual(speed, 50)
            }
        }
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

    func testMercedesEQA250DoesNotPublishDisprovenSOCFromDriveCapture() {
        let profile = MercedesEQA250Profile()
        // 2026-09-06 post-drive capture: car dashboard 81%, old formula ~96.6%.
        for (status, value) in [("04", "3E BC"), ("02", "3E CC"), ("00", "3E D0")] {
            let raw = "18 DA F1 59 10 0B 62 02 10 \(status) 00 00\r18 DA F1 59 21 \(value) 00 00 00 AA AA\r>"
            XCTAssertFalse(ISO15765Parser().assembleISOTPPayload(raw).isEmpty)
            for command in ["220210", "22 02 10"] {
                XCTAssertNil(profile.parseResponse(command: command, rawResponse: raw))
                XCTAssertTrue(profile.parseResponses(command: command, rawResponse: raw).isEmpty)
            }
        }
        XCTAssertFalse(profile.supportedMetrics.contains(.soc))
        XCTAssertTrue(profile.pollingCommands.contains("220210"), "Keep the raw DID available for capture")
    }

    func testMercedesEQA250FullChargeMatchDoesNotValidateSOC() {
        let profile = MercedesEQA250Profile()
        // Real ECU 0x59 capture while the dashboard displayed 100% during AC charging.
        let rawResponse = "18 DA F1 59 10 0B 62 02 10 04 00 00\r\n18 DA F1 59 21 40 F4 00 00 00 AA AA\r\n>"

        XCTAssertNil(profile.parseResponse(command: "220210", rawResponse: rawResponse))
    }

    func testMercedesEQA250TruncatedReplyDoesNotDecodeSOC() {
        let profile = MercedesEQA250Profile()
        // Enough bytes for the SOC formula, but fewer than the declared 11-byte payload.
        for header in ["18 DA F1 59", "18DAF159"] {
            let raw = "\(header) 10 0B 62 02 10 04 00 00\r\(header) 21 39 90\r>"
            XCTAssertTrue(ISO15765Parser().assembleISOTPPayload(raw).isEmpty)
            XCTAssertNil(profile.parseResponse(command: "220210", rawResponse: raw))
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

    func testMercedesEQA250DoesNotAdvertiseUnsupportedPackCurrent() {
        let profile = MercedesEQA250Profile()
        let rawResponse = "18 DA F1 59 03 7F 22 31\r\n>"

        XCTAssertNil(profile.parseResponse(command: "22010B", rawResponse: rawResponse))
        XCTAssertFalse(profile.pollingCommands.contains("22010B"))
        XCTAssertFalse(profile.supportedMetrics.contains(.packCurrent))
        XCTAssertFalse(profile.supportedMetrics.contains(.power))
    }

    func testMercedesEQA250DoesNotDecodeSyntheticBatteryTemperature() {
        let profile = MercedesEQA250Profile()
        let rawResponse = "18 DA F1 59 04 62 01 0C 41\r\n>"

        XCTAssertNil(profile.parseResponse(command: "22010C", rawResponse: rawResponse))
    }

    func testMercedesEQA250StatusByteDoesNotEmitNegative32BatteryTemperature() {
        let profile = MercedesEQA250Profile()
        let rawResponse = "18 DA F1 59 04 62 01 0C 08\r\n>"

        XCTAssertNil(profile.parseResponse(command: "22010C", rawResponse: rawResponse))
    }

    func testMercedesEQA250DoesNotPollOrAdvertiseUnverifiedBatteryTemperature() {
        let profile = MercedesEQA250Profile()

        XCTAssertFalse(profile.pollingCommands.contains("22010C"))
        XCTAssertFalse(profile.supportedMetrics.contains(.batteryTemp))
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

    /// `parseResponses` emits SOH alongside SOC (from 220105) and 12V aux alongside pack
    /// power (from 220101) — both live in the same payload as the primary metric.
    func testEGMPEmitsSOHAndAux12VAlongsidePrimaryMetrics() {
        let profile = HyundaiKiaEGMPProfile()

        var payload101 = [String](repeating: "00", count: 31)
        payload101[10] = "FF"; payload101[11] = "9C" // current -10.0 A
        payload101[13] = "0E"; payload101[14] = "74" // voltage 370.0 V
        payload101[30] = "8A" // aux12V -> 138 * 0.1 = 13.8 V
        let raw101 = "62 01 01 " + payload101.joined(separator: " ") + "\r\n>"
        let updates101 = profile.parseResponses(command: "220101", rawResponse: raw101)

        XCTAssertEqual(updates101.count, 2)
        guard case .power(let voltage, let current, let powerKW)? = updates101.first(where: {
            if case .power = $0 { return true } else { return false }
        }) else { return XCTFail("Expected power update, got \(updates101)") }
        XCTAssertEqual(voltage, 370.0, accuracy: 0.01)
        XCTAssertEqual(current, -10.0, accuracy: 0.01)
        XCTAssertEqual(powerKW, -3.7, accuracy: 0.01)
        guard case .aux12V(let aux)? = updates101.first(where: {
            if case .aux12V = $0 { return true } else { return false }
        }) else { return XCTFail("Expected aux12V update, got \(updates101)") }
        XCTAssertEqual(aux, 13.8, accuracy: 0.01)

        var payload105 = [String](repeating: "00", count: 33)
        payload105[26] = "03"; payload105[27] = "DE" // soh 990/10 = 99.0
        payload105[32] = "64" // soc 100/2 = 50.0
        let raw105 = "62 01 05 " + payload105.joined(separator: " ") + "\r\n>"
        let updates105 = profile.parseResponses(command: "220105", rawResponse: raw105)

        XCTAssertEqual(updates105.count, 2)
        guard case .soc(let soc)? = updates105.first(where: {
            if case .soc = $0 { return true } else { return false }
        }) else { return XCTFail("Expected soc update, got \(updates105)") }
        XCTAssertEqual(soc, 50.0, accuracy: 0.01)
        guard case .soh(let soh)? = updates105.first(where: {
            if case .soh = $0 { return true } else { return false }
        }) else { return XCTFail("Expected soh update, got \(updates105)") }
        XCTAssertEqual(soh, 99.0, accuracy: 0.01)

        XCTAssertTrue(profile.supportedMetrics.isSuperset(of: [.soh, .aux12V]))
    }

    func testDTCLookup() {
        let db = DTCLocalDatabase.shared
        let code = db.lookup(code: "P0A80")
        XCTAssertEqual(code.code, "P0A80")
        XCTAssertEqual(code.severity, .critical)
        XCTAssertTrue(code.title.contains("Replace Hybrid/EV Battery Pack"))
    }

    func testImportedDTCDefinitionsAndManufacturerIsolation() throws {
        let db = DTCLocalDatabase.shared
        XCTAssertNil(db.loadError)
        let generic = db.lookup(code: " p0301 ", manufacturer: "Audi")
        XCTAssertEqual(generic.title, "Cylinder 1 Misfire Detected")
        XCTAssertEqual(generic.severity, .unknown)
        XCTAssertTrue(generic.symptoms.isEmpty)
        XCTAssertTrue(generic.possibleFixes.isEmpty)
        XCTAssertTrue(generic.definitionSource?.contains("Wal33D") == true)
        let decoded = try JSONDecoder().decode(DTCCode.self, from: JSONEncoder().encode(generic))
        XCTAssertEqual(decoded.definitionSource, generic.definitionSource)
        XCTAssertEqual(db.lookup(code: "P1105", manufacturer: "Mercedes-Benz").title,
                       "Atmospheric Pressure Sensor In Control Module")
        XCTAssertEqual(db.lookup(code: "P1105", manufacturer: "Ford").title,
                       "Dual Alternator Upper Fault")
        for manufacturer in [nil, "Unknown brand", "GENERIC"] as [String?] {
            XCTAssertEqual(db.lookup(code: "P1105", manufacturer: manufacturer).title,
                           "Diagnostic Code P1105")
        }
        XCTAssertEqual(db.lookup(code: "P1000").title, "Diagnostic Code P1000",
                       "Manufacturer-controlled placeholders must not look like definitions")
    }

    func testDTCScanUsesManufacturerForStoredAndPendingAndResetsContext() {
        let scanner = DTCScannerService()
        let connection = ScriptedConnection(response: .success("43 01 11 05\r>"))
        connection.responses["07"] = .success("47 01 14 81\r>")
        scanner.scanDTCs(connection: connection, manufacturer: "Mercedes-Benz")
        XCTAssertTrue(scanner.scanSucceeded)
        XCTAssertEqual(scanner.scannedCodes.map(\.title),
                       ["Atmospheric Pressure Sensor In Control Module", "Glow Plug Failure"])
        scanner.scanDTCs(connection: connection)
        XCTAssertEqual(scanner.scannedCodes.first?.title, "Diagnostic Code P1105")
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
        // 6 FF bytes + 7 CF bytes = 13 (0x0D), not 14.
        let raw = "7E8 10 0D 43 04 01 43 01 33\r\n7E8 21 02 47 03 01 00 00 00\r\n>"
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

        XCTAssertEqual(Array(connection.sentCommands.prefix(8)), BluetoothManager.diagnosticSetupCommands + ["03"])
        XCTAssertEqual(connection.sentCommands.suffix(2).map { $0 }, ["ATCRA 18DAF159", "AT SH 18DA59F1"])
        XCTAssertTrue(scanner.scanSucceeded)
    }

    func testDiagnosticErrorsNeverBecomeHealthyAndPendingFailureIsPartial() {
        for raw in ["?\r>", "ERROR\r>", "\r>", "43 02 0A 80\r>", "41 0D 00\r>"] {
            let scanner = DTCScannerService()
            scanner.scanDTCs(connection: ScriptedConnection(response: .success(raw)))
            XCTAssertFalse(scanner.scanSucceeded, raw)
            XCTAssertNotNil(scanner.scanErrorMessage, raw)
        }
        let scanner = DTCScannerService()
        let connection = ScriptedConnection(response: .success("43 01 0A 80\r>"))
        connection.responses["07"] = .success("NO DATA\r>")
        scanner.scanDTCs(connection: connection)
        XCTAssertEqual(scanner.scannedCodes.map(\.code), ["P0A80"])
        XCTAssertFalse(scanner.scanSucceeded)
        XCTAssertTrue(scanner.scanErrorMessage?.contains("Partial") == true)
    }

    func testScanWaitsForRestorationAndDisconnectsIfItFails() {
        let scanner = DTCScannerService()
        let connection = ScriptedConnection(response: .success("43 00\r>"))
        connection.heldCommand = "AT SH 18DA59F1"
        var finished = false
        scanner.scanDTCs(connection: connection, restoreCommands: [connection.heldCommand!]) { finished = true }
        XCTAssertTrue(scanner.isScanning)
        XCTAssertFalse(finished)
        connection.heldCompletion?(.success("?\r>"))
        XCTAssertTrue(finished)
        XCTAssertFalse(scanner.isScanning)
        XCTAssertFalse(scanner.scanSucceeded)
        XCTAssertEqual(connection.state, .disconnected)
    }

    func testClearUsesDiagnosticSetupThenRestoresProfileBeforePolling() {
        let connection = ScriptedConnection(response: .success("7E8 01 44\r>"))
        let manager = VehicleDataManager(connection: connection)
        let scanner = DTCScannerService()
        var cleared = false
        scanner.clearDTCs(vehicleData: manager) { cleared = $0 }
        manager.stopPolling()
        XCTAssertTrue(cleared)
        XCTAssertFalse(manager.isCommandSessionActive)
        let expected = BluetoothManager.diagnosticSetupCommands(for: manager.selectedProfile.initializationCommands) + ["04"] + manager.selectedProfile.initializationCommands
        XCTAssertEqual(Array(connection.sentCommands.prefix(expected.count)), expected)
        XCTAssertFalse(scanner.scanSucceeded, "Clearing is not a complete diagnostic rescan")
    }

    func testSetupFailureDoesNotSendDiagnosticService() {
        let connection = ScriptedConnection(response: .success("43 00\r>"))
        connection.responses["AT CAF 1"] = .success("?\r>")
        let scanner = DTCScannerService()
        scanner.scanDTCs(connection: connection, restoreCommands: ["AT E0"])
        XCTAssertFalse(connection.sentCommands.contains("03"))
        XCTAssertFalse(scanner.scanSucceeded)
        XCTAssertNotNil(scanner.scanErrorMessage)
    }

    func testDiagnosticSetupRetainsBusProtocolButResetsRawFramingAndAddressing() {
        for profile in [MercedesEQA250Profile(), VolkswagenMEBProfile()] as [VehicleProfile] {
            let setup = BluetoothManager.diagnosticSetupCommands(for: profile.initializationCommands)
            XCTAssertEqual(setup.first, "AT Z")
            XCTAssertEqual(setup.last, "AT SP 7")
            XCTAssertTrue(setup.contains("AT CAF 1"))
            XCTAssertFalse(setup.contains { $0.hasPrefix("AT SH") || $0.hasPrefix("AT CP") || $0.hasPrefix("AT CRA") })
        }
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

    /// `INT16(hi:lo)` is pre-processed into `((Signed(hi)*256)+lo)` before evaluation, so the
    /// Mini's SOC equation now evaluates instead of being rejected as non-arithmetic.
    func testABRPEvaluatesINT16Equation() throws {
        let mini = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "Mini_MiniCooperSE.json"))
        guard case .soc(let pct)? = mini.parseResponse(command: "22DDBC", rawResponse: "607 05 62 DD BC 02 EE\r\n>") else {
            return XCTFail("Expected SOC update")
        }
        XCTAssertEqual(pct, 75.0, accuracy: 0.01)
    }

    /// Genuinely malformed equations must still be rejected, not handed to
    /// `NSExpression(format:)` where they raise an uncatchable ObjC exception.
    func testABRPStillRejectsMalformedEquations() throws {
        let json = """
        {
            "init_commands": {"command": ["ATZ"]},
            "data_commands": {"command": ["22DDBC"]},
            "obd_protocol": "6",
            "soc": {"equation": "GARBAGE(A;B", "minValue": "0", "maxValue": "100", "type": "Number", "command": "22DDBC"}
        }
        """
        let def = try JSONDecoder().decode(ABRPProfileDefinition.self, from: try XCTUnwrap(json.data(using: .utf8)))
        let profile = ABRPGenericVehicleProfile(name: "Malformed", capacityKWh: 50.0, definition: def)
        XCTAssertNil(profile.parseResponse(command: "22DDBC", rawResponse: "607 05 62 DD BC 02 EE\r\n>"))
    }

    /// Lowercase two-letter tokens (spreadsheet-column addressing past byte 25) previously
    /// never matched the single-letter A-Z fast path, so `hkmc_hkmc2019.json`'s `af/2` SOC
    /// equation silently never evaluated.
    func testABRPEvaluatesLowercaseTwoLetterTokens() throws {
        let hkmc = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "hkmc_hkmc2019.json"))
        var payload = [String](repeating: "00", count: 32)
        payload[31] = "A0" // af -> byte 31; 0xA0 = 160 -> /2 = 80.0
        let raw = "62 01 05 " + payload.joined(separator: " ") + "\r\n>"
        let updates = hkmc.parseResponses(command: "220105", rawResponse: raw)

        guard case .soc(let pct)? = updates.first(where: { if case .soc = $0 { return true } else { return false } }) else {
            return XCTFail("Expected SOC update, got \(updates)")
        }
        XCTAssertEqual(pct, 80.0, accuracy: 0.01)
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

    /// One `220101` reply on the IONIQ 5 / EV6 profile carries current, voltage, and the
    /// charging-status bit all at once — `parseResponses` must emit all three.
    func testABRPParseResponsesEmitsAllMetricsForOneCommand() throws {
        let ioniq5 = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "hkmc_Ioniq5.json"))
        var payload = [String](repeating: "00", count: 15)
        payload[9] = "02"  // {j:1} charging bit set
        payload[10] = "FF"; payload[11] = "9C" // current -10.0 A
        payload[13] = "0E"; payload[14] = "74" // voltage 370.0 V
        let raw = "62 01 01 " + payload.joined(separator: " ") + "\r\n>"
        let updates = ioniq5.parseResponses(command: "220101", rawResponse: raw)

        guard case .packCurrent(let amps)? = updates.first(where: {
            if case .packCurrent = $0 { return true } else { return false }
        }) else { return XCTFail("Expected packCurrent update, got \(updates)") }
        XCTAssertEqual(amps, -10.0, accuracy: 0.01)

        guard case .packVoltage(let volts)? = updates.first(where: {
            if case .packVoltage = $0 { return true } else { return false }
        }) else { return XCTFail("Expected packVoltage update, got \(updates)") }
        XCTAssertEqual(volts, 370.0, accuracy: 0.01)

        guard case .chargingStats(let kwRate, _)? = updates.first(where: {
            if case .chargingStats = $0 { return true } else { return false }
        }) else { return XCTFail("Expected chargingStats update, got \(updates)") }
        XCTAssertNil(kwRate)
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
