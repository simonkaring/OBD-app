import Foundation
import CoreBluetooth
import VoltLinkEngine

// MARK: - 1. Scan Command

struct ScanCommand: @unchecked Sendable {
    final class Scanner: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
        private var central: CBCentralManager!
        private var discovered: [(name: String, id: UUID, rssi: Int, isOBD: Bool)] = []
        private var isDone = false
        
        func run(seconds: Double) async -> [(name: String, id: UUID, rssi: Int, isOBD: Bool)] {
            central = CBCentralManager(delegate: self, queue: nil)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            central.stopScan()
            return discovered
        }
        
        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            }
        }
        
        func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "<Unnamed>"
            let lower = name.lowercased()
            let keywords = ["vlink", "ios-vlink", "icar", "obd", "ble", "veepeak", "link", "elm", "konnwei", "lelink"]
            let isOBD = keywords.contains { lower.contains($0) }
            
            if !discovered.contains(where: { $0.id == peripheral.identifier }) {
                discovered.append((name: name, id: peripheral.identifier, rssi: RSSI.intValue, isOBD: isOBD))
            }
        }
    }
    
    static func run(args: [String]) async {
        print("🔍 Scanning for Bluetooth LE devices (5s)...")
        let scanner = Scanner()
        let devices = await scanner.run(seconds: 5.0)
        
        if devices.isEmpty {
            print("No BLE devices discovered.")
            return
        }
        
        print("\nDiscovered Devices:")
        print("----------------------------------------------------------------------")
        print(String(format: "%-25s %-38s %-6s %s", "NAME", "UUID", "RSSI", "TYPE"))
        print("----------------------------------------------------------------------")
        for dev in devices.sorted(by: { $0.rssi > $1.rssi }) {
            let typeTag = dev.isOBD ? "🚗 OBD-II Adapter" : "BLE Peripheral"
            let nameStr = String(dev.name.prefix(24))
            print(String(format: "%-25s %-38s %-6d %s", nameStr, dev.id.uuidString, dev.rssi, typeTag))
        }
        print("----------------------------------------------------------------------\n")
    }
}

// MARK: - 2. Raw Command

struct RawCommand {
    static func run(args: [String]) async {
        guard !args.isEmpty else {
            print("❌ Error: No command specified. Example: voltlink-cli raw \"ATI\" \"ATRV\"")
            return
        }
        
        print("Connecting to OBD adapter...")
        let client = AsyncOBDClient()
        do {
            try await client.connect()
            print("Connected! Sending \(args.count) command(s):\n")
            
            for cmd in args {
                let start = Date()
                let response = try await client.sendRaw(cmd)
                let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
                let clean = response.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                print("[\(elapsedMs)ms] \(cmd) ➔ \(clean)")
            }
            
            client.disconnect()
        } catch {
            print("❌ Connection / Command Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - 3. Interactive REPL

struct REPLCommand {
    static func run(args: [String]) async {
        print("Connecting to OBD adapter...")
        let client = AsyncOBDClient()
        do {
            try await client.connect()
            print("""
            =====================================================
            ⚡️ VoltLink Interactive OBD Shell
            Type any ELM327 / OBD / UDS command (e.g. 'ATI', 'ATRV', '0100')
            Type 'exit' or 'quit' to end session.
            =====================================================
            """)
            
            while true {
                print("OBD> ", terminator: "")
                guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
                    continue
                }
                
                if line.lowercased() == "exit" || line.lowercased() == "quit" {
                    break
                }
                
                let start = Date()
                do {
                    let response = try await client.sendRaw(line)
                    let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
                    let clean = response.replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    print("[\(elapsedMs)ms]\n\(clean)\n")
                } catch {
                    print("❌ Error: \(error.localizedDescription)\n")
                }
            }
            
            client.disconnect()
            print("Disconnected.")
        } catch {
            print("❌ Connection Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - 4. UDS DID Probe Command

struct ProbeCommand {
    struct ProbeEntry: Codable {
        let ecu: String
        let did: String
        let status: String
        let rawResponse: String
        let payload: String
        let elapsedMs: Int
    }
    
    static func run(args: [String]) async {
        var ecus = ["59", "29", "17"]
        var startDID = 0x0100
        var endDID = 0x0130
        var jsonOutput = false
        var showAll = false
        
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--ecu":
                if i + 1 < args.count {
                    ecus = args[i + 1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    i += 1
                }
            case "--start":
                if i + 1 < args.count {
                    startDID = Int(args[i + 1].replacingOccurrences(of: "0x", with: ""), radix: 16) ?? startDID
                    i += 1
                }
            case "--end":
                if i + 1 < args.count {
                    endDID = Int(args[i + 1].replacingOccurrences(of: "0x", with: ""), radix: 16) ?? endDID
                    i += 1
                }
            case "--json":
                jsonOutput = true
            case "--all":
                showAll = true
            default:
                break
            }
            i += 1
        }
        
        if !jsonOutput {
            print("⚡️ Probing UDS DIDs 0x\(String(format: "%04X", startDID)) - 0x\(String(format: "%04X", endDID)) on ECUs: \(ecus.joined(separator: ", "))")
            print("Connecting to OBD adapter...")
        }
        
        let client = AsyncOBDClient()
        let parser = ISO15765Parser()
        var results: [ProbeEntry] = []
        
        do {
            try await client.connect()
            try await client.initializeELM327(protocolNumber: "7")
            
            for ecu in ecus {
                if !jsonOutput {
                    print("\n--- Testing ECU 0x\(ecu) (Header: 18DA\(ecu)F1) ---")
                }
                _ = try? await client.sendRaw("AT SH 18DA\(ecu)F1")
                _ = try? await client.sendRaw("AT CRA")
                
                for didVal in startDID...endDID {
                    let didHex = String(format: "%04X", didVal)
                    let cmd = "22 \(didHex)"
                    let start = Date()
                    let raw = (try? await client.sendRaw(cmd)) ?? "TIMEOUT"
                    let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
                    
                    let clean = raw.replacingOccurrences(of: ">", with: "")
                        .replacingOccurrences(of: "\r", with: " ")
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                    
                    let payload = parser.assembleISOTPPayload(raw)
                    let noSpace = clean.replacingOccurrences(of: " ", with: "")
                    
                    let status: String
                    if noSpace.contains("62\(didHex)") || (payload.starts(with: "62") && payload.count > 6) {
                        status = "POSITIVE"
                    } else if noSpace.contains("7F2231") {
                        status = "NOT_SUPPORTED"
                    } else if noSpace.contains("7F22") {
                        status = "NRC_REJECTED"
                    } else if noSpace.contains("NODATA") || noSpace.contains("UNABLE") {
                        status = "NO_DATA"
                    } else {
                        status = "UNKNOWN"
                    }
                    
                    let entry = ProbeEntry(ecu: ecu, did: didHex, status: status, rawResponse: clean, payload: payload, elapsedMs: elapsedMs)
                    results.append(entry)
                    
                    if !jsonOutput {
                        if status == "POSITIVE" {
                            print("  ✅ [\(elapsedMs)ms] ECU \(ecu) DID \(didHex) ➔ Payload: \(payload)")
                        } else if showAll || (status != "NOT_SUPPORTED" && status != "NO_DATA") {
                            print("  ⚠️ [\(elapsedMs)ms] ECU \(ecu) DID \(didHex) ➔ \(status) (\(clean))")
                        }
                    }
                    
                    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms pacing
                }
            }
            
            client.disconnect()
            
            if jsonOutput {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(results), let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                let positiveHits = results.filter { $0.status == "POSITIVE" }
                print("\n=====================================================")
                print("Probe complete: Found \(positiveHits.count) positive DIDs across \(ecus.count) ECUs.")
                for hit in positiveHits {
                    print("  - ECU \(hit.ecu) DID 0x\(hit.did): \(hit.payload)")
                }
                print("=====================================================\n")
            }
        } catch {
            print("❌ Probe error: \(error.localizedDescription)")
        }
    }
}

// MARK: - 5. DTC Command

struct DTCCommand {
    static func run(args: [String]) async {
        let shouldClear = args.contains("--clear") || args.contains("-c")
        
        print("Connecting to OBD adapter...")
        let client = AsyncOBDClient()
        let database = DTCLocalDatabase.shared
        
        do {
            try await client.connect()
            _ = try await client.sendRaw("AT Z")
            _ = try await client.sendRaw("AT E0")
            _ = try await client.sendRaw("AT SP 0") // Auto protocol for Mode 03
            
            if shouldClear {
                print("Clearing Diagnostic Trouble Codes (Mode 04)...")
                let resp = try await client.sendRaw("04")
                print("Result: \(resp.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                print("Querying Stored DTCs (Mode 03)...")
                let raw03 = try await client.sendRaw("03")
                print("Mode 03 Response: \(raw03.trimmingCharacters(in: .whitespacesAndNewlines))")
                
                print("\nQuerying Pending DTCs (Mode 07)...")
                let raw07 = try await client.sendRaw("07")
                print("Mode 07 Response: \(raw07.trimmingCharacters(in: .whitespacesAndNewlines))")
                
                let parser = ISO15765Parser()
                let p03 = parser.assembleISOTPPayload(raw03)
                let p07 = parser.assembleISOTPPayload(raw07)
                
                var dtcs: [String] = []
                dtcs.append(contentsOf: parseDTCBytes(p03, servicePrefix: "43"))
                dtcs.append(contentsOf: parseDTCBytes(p07, servicePrefix: "47"))
                
                print("\n=====================================================")
                if dtcs.isEmpty {
                    print("✅ No Diagnostic Trouble Codes reported.")
                } else {
                    print("⚠️ Found \(dtcs.count) Trouble Code(s):")
                    for code in dtcs {
                        let desc = database.lookup(code: code).description
                        print("  - \(code): \(desc)")
                    }
                }
                print("=====================================================\n")
            }
            
            client.disconnect()
        } catch {
            print("❌ DTC Scanner error: \(error.localizedDescription)")
        }
    }
    
    private static func parseDTCBytes(_ payload: String, servicePrefix: String) -> [String] {
        guard payload.hasPrefix(servicePrefix) else { return [] }
        var clean = String(payload.dropFirst(servicePrefix.count))
        // If there's a count byte (e.g. 43 01 ...), check
        if clean.count % 4 != 0 && clean.count >= 2 {
            clean = String(clean.dropFirst(2))
        }
        
        var dtcs: [String] = []
        var index = clean.startIndex
        while clean.distance(from: index, to: clean.endIndex) >= 4 {
            let nextIndex = clean.index(index, offsetBy: 4)
            let pair = String(clean[index..<nextIndex])
            if pair != "0000", let code = decodeDTC(hexPair: pair) {
                dtcs.append(code)
            }
            index = nextIndex
        }
        return dtcs
    }
    
    private static func decodeDTC(hexPair: String) -> String? {
        guard hexPair.count == 4, let val = UInt16(hexPair, radix: 16) else { return nil }
        let typeNibble = (val >> 14) & 0x03
        let typeString: String
        switch typeNibble {
        case 0: typeString = "P"
        case 1: typeString = "C"
        case 2: typeString = "B"
        case 3: typeString = "U"
        default: typeString = "P"
        }
        let remainder = val & 0x3FFF
        return String(format: "%@%04X", typeString, remainder)
    }
}

// MARK: - 6. Live Monitor Command

struct MonitorCommand {
    static func run(args: [String]) async {
        let isGeneric = args.contains("generic")
        let profile: any VehicleProfile = isGeneric ? GenericOBD2Profile() : MercedesEQA250Profile()
        
        print("⚡️ Live Telemetry Monitor using profile: \(profile.vehicleName)")
        print("Connecting to OBD adapter...")
        
        let client = AsyncOBDClient()
        
        do {
            try await client.connect()
            print("Connected! Initializing vehicle profile...\n")
            
            for cmd in profile.initializationCommands {
                _ = try await client.sendRaw(cmd)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            
            print("Streaming live telemetry (Press Ctrl+C to stop)...\n")
            var snapshot = TelemetrySnapshot()
            
            while true {
                for cmd in profile.pollingCommands {
                    let raw = try await client.sendRaw(cmd)
                    if let update = profile.parseResponse(command: cmd, rawResponse: raw) {
                        applyUpdate(update, to: &snapshot)
                    }
                    try? await Task.sleep(nanoseconds: 30_000_000)
                }
                
                print(String(format: "\r⚡ SoC: %5.1f%% | Pwr: %6.1f kW | Spd: %3.0f km/h | 12V: %4.1fV | BatTemp: %4.1f°C",
                             snapshot.stateOfChargePct,
                             snapshot.powerKW,
                             snapshot.speedKmH,
                             snapshot.aux12VVolts,
                             snapshot.batteryTempC), terminator: "")
                fflush(stdout)
            }
        } catch {
            print("\n❌ Monitor error: \(error.localizedDescription)")
        }
    }
    
    private static func applyUpdate(_ update: TelemetryUpdate, to snapshot: inout TelemetrySnapshot) {
        switch update {
        case .soc(let val): snapshot.stateOfChargePct = val
        case .power(_, _, let kw): snapshot.powerKW = kw
        case .speed(let val): snapshot.speedKmH = val
        case .aux12V(let val): snapshot.aux12VVolts = val
        case .batteryTemp(_, _, let avg): snapshot.batteryTempC = avg
        default: break
        }
    }
}
