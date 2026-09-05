import Foundation

/// Represents a metric definition in an ABRP (A Better Routeplanner) PID configuration JSON.
public struct ABRPMetricDefinition: Codable, Sendable {
    public let equation: String
    public let minValue: String?
    public let maxValue: String?
    public let type: String?
    public let command: String?
    public let ecu: String?
}

/// Models the JSON file format from `iternio/ev-obd-pids`.
public struct ABRPProfileDefinition: Codable, Sendable {
    public let initCommands: [String]
    public let dataCommands: [String]
    public let obdProtocol: String?
    public let current: ABRPMetricDefinition?
    public let voltage: ABRPMetricDefinition?
    public let soc: ABRPMetricDefinition?
    public let soh: ABRPMetricDefinition?
    public let battTemp: ABRPMetricDefinition?
    public let extTemp: ABRPMetricDefinition?
    public let speed: ABRPMetricDefinition?
    public let isCharging: ABRPMetricDefinition?
    
    enum CodingKeys: String, CodingKey {
        case initCommandsObj = "init_commands"
        case initCommandsObjCaps = "Init_Commands"
        case dataCommandsObj = "data_commands"
        case dataCommandsObjCaps = "Data_Commands"
        case obdProtocol = "obd_protocol"
        case current
        case voltage
        case soc
        case soh
        case battTemp = "batt_temp"
        case extTemp = "ext_temp"
        case speed
        case isCharging = "is_charging"
    }

    private struct CommandList: Codable {
        let command: [String]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        var inits: [String] = []
        if let list = try? container.decode(CommandList.self, forKey: .initCommandsObj) {
            inits = list.command
        } else if let list = try? container.decode(CommandList.self, forKey: .initCommandsObjCaps) {
            inits = list.command
        }
        self.initCommands = inits
        
        var datas: [String] = []
        if let list = try? container.decode(CommandList.self, forKey: .dataCommandsObj) {
            datas = list.command
        } else if let list = try? container.decode(CommandList.self, forKey: .dataCommandsObjCaps) {
            datas = list.command
        }
        self.dataCommands = datas
        
        self.obdProtocol = try? container.decode(String.self, forKey: .obdProtocol)
        self.current = try? container.decode(ABRPMetricDefinition.self, forKey: .current)
        self.voltage = try? container.decode(ABRPMetricDefinition.self, forKey: .voltage)
        self.soc = try? container.decode(ABRPMetricDefinition.self, forKey: .soc)
        self.soh = try? container.decode(ABRPMetricDefinition.self, forKey: .soh)
        self.battTemp = try? container.decode(ABRPMetricDefinition.self, forKey: .battTemp)
        self.extTemp = try? container.decode(ABRPMetricDefinition.self, forKey: .extTemp)
        self.speed = try? container.decode(ABRPMetricDefinition.self, forKey: .speed)
        self.isCharging = try? container.decode(ABRPMetricDefinition.self, forKey: .isCharging)
    }

    public func encode(to encoder: Encoder) throws {}
}

/// Generic vehicle profile executing ABRP JSON formulas dynamically.
public struct ABRPGenericVehicleProfile: VehicleProfile {
    public let vehicleName: String
    public let isElectricVehicle: Bool = true
    public let batteryUsableCapacityKWh: Double
    public let definition: ABRPProfileDefinition

    private let isoParser = ISO15765Parser()

    public init(name: String, capacityKWh: Double = 70.0, definition: ABRPProfileDefinition) {
        self.vehicleName = name
        self.batteryUsableCapacityKWh = capacityKWh
        self.definition = definition
    }

    public var initializationCommands: [String] {
        if !definition.initCommands.isEmpty {
            return definition.initCommands
        }
        let proto = definition.obdProtocol ?? "6"
        return ["AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT ST FF", "AT SP \(proto)"]
    }

    public var pollingCommands: [String] {
        definition.dataCommands
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        var set: Set<TelemetryMetric> = []
        if definition.soc != nil { set.insert(.soc) }
        if definition.voltage != nil { set.insert(.packVoltage) }
        if definition.current != nil { set.insert(.packCurrent) }
        if definition.voltage != nil && definition.current != nil { set.insert(.power) }
        if definition.soh != nil { set.insert(.soh) }
        if definition.battTemp != nil { set.insert(.batteryTemp) }
        if definition.speed != nil { set.insert(.speed) }
        if definition.extTemp != nil { set.insert(.ambientAirTemp) }
        // `is_charging` feeds `snapshot.isCharging` via `.chargingStats` only — it has no
        // dashboard tile of its own, so it is not advertised as a supported metric.
        return set
    }

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        // ABRP equations address bytes positionally (A = byte 0 after the DID echo), so the
        // response must be reassembled first: on a multi-frame reply the raw text still
        // carries CAN IDs and ISO-TP PCI bytes interleaved between the data bytes.
        let hex = isoParser.assembleISOTPPayload(rawResponse)
        guard !hex.isEmpty else { return nil }

        let bytes = extractBytes(from: hex, command: command)
        guard !bytes.isEmpty else { return nil }

        // Check if command matches SOC
        if let socDef = definition.soc, matchesCommand(socDef.command, currentCommand: command) {
            if let val = evaluate(equation: socDef.equation, bytes: bytes) {
                return .soc(min(100.0, max(0.0, val)))
            }
        }

        // Check if command matches Voltage
        if let voltDef = definition.voltage, matchesCommand(voltDef.command, currentCommand: command) {
            if let v = evaluate(equation: voltDef.equation, bytes: bytes) {
                return .packVoltage(v)
            }
        }

        // Check if command matches Current
        if let currDef = definition.current, matchesCommand(currDef.command, currentCommand: command) {
            if let a = evaluate(equation: currDef.equation, bytes: bytes) {
                // Emit standalone current; the manager multiplies it by the last
                // parsed pack voltage rather than a fabricated nominal one.
                return .packCurrent(a)
            }
        }

        // Check if command matches State of Health
        if let sohDef = definition.soh, matchesCommand(sohDef.command, currentCommand: command) {
            if let v = evaluate(equation: sohDef.equation, bytes: bytes) {
                return .soh(min(100.0, max(0.0, v)))
            }
        }

        // Check if command matches Battery Temp
        if let tempDef = definition.battTemp, matchesCommand(tempDef.command, currentCommand: command) {
            if let t = evaluate(equation: tempDef.equation, bytes: bytes) {
                return .batteryTemp(min: t, max: t, avg: t)
            }
        }

        // Check if command matches Speed
        if let spdDef = definition.speed, matchesCommand(spdDef.command, currentCommand: command) {
            if let s = evaluate(equation: spdDef.equation, bytes: bytes) {
                return .speed(max(0.0, s))
            }
        }

        return nil
    }

    /// Unlike `parseResponse` (first-matching-metric priority, kept for existing callers),
    /// this evaluates EVERY metric definition whose `command` matches the current response —
    /// e.g. one E-GMP `220101` reply carries current, voltage, and the charging-status bit.
    public func parseResponses(command: String, rawResponse: String) -> [TelemetryUpdate] {
        let buckets = isoParser.assembleISOTPPayloads(rawResponse)
        guard !buckets.isEmpty else { return [] }
        let concatenatedHex = buckets.map(\.payload).joined()

        // ECU-aware bucket selection: prefer the bucket whose key matches (or is suffixed
        // by) the metric definition's ECU; fall back to the concatenated hex otherwise.
        func bytes(for def: ABRPMetricDefinition) -> [UInt8] {
            var hex = concatenatedHex
            if let ecu = def.ecu?.uppercased(), !ecu.isEmpty,
               let match = buckets.first(where: { $0.ecu.uppercased() == ecu || $0.ecu.uppercased().hasSuffix(ecu) }) {
                hex = match.payload
            }
            return extractBytes(from: hex, command: command)
        }

        var updates: [TelemetryUpdate] = []

        if let def = definition.soc, matchesCommand(def.command, currentCommand: command) {
            let b = bytes(for: def)
            if !b.isEmpty, let v = evaluate(equation: def.equation, bytes: b) {
                updates.append(.soc(min(100.0, max(0.0, v))))
            }
        }

        if let def = definition.voltage, matchesCommand(def.command, currentCommand: command) {
            let b = bytes(for: def)
            if !b.isEmpty, let v = evaluate(equation: def.equation, bytes: b) {
                updates.append(.packVoltage(v))
            }
        }

        if let def = definition.current, matchesCommand(def.command, currentCommand: command) {
            let b = bytes(for: def)
            if !b.isEmpty, let v = evaluate(equation: def.equation, bytes: b) {
                updates.append(.packCurrent(v))
            }
        }

        if let def = definition.soh, matchesCommand(def.command, currentCommand: command) {
            let b = bytes(for: def)
            if !b.isEmpty, let v = evaluate(equation: def.equation, bytes: b) {
                updates.append(.soh(min(100.0, max(0.0, v))))
            }
        }

        if let def = definition.battTemp, matchesCommand(def.command, currentCommand: command) {
            let b = bytes(for: def)
            if !b.isEmpty, let v = evaluate(equation: def.equation, bytes: b) {
                updates.append(.batteryTemp(min: v, max: v, avg: v))
            }
        }

        if let def = definition.speed, matchesCommand(def.command, currentCommand: command) {
            let b = bytes(for: def)
            if !b.isEmpty, let v = evaluate(equation: def.equation, bytes: b) {
                updates.append(.speed(max(0.0, v)))
            }
        }

        if let def = definition.extTemp, matchesCommand(def.command, currentCommand: command) {
            let b = bytes(for: def)
            if !b.isEmpty, let v = evaluate(equation: def.equation, bytes: b) {
                updates.append(.ambientAirTemp(v))
            }
        }

        if let def = definition.isCharging, matchesCommand(def.command, currentCommand: command) {
            let b = bytes(for: def)
            if !b.isEmpty, let v = evaluate(equation: def.equation, bytes: b), v > 0.5 {
                updates.append(.chargingStats(kwRate: nil, acOrDc: ""))
            }
        }

        return updates
    }

    /// Exact match only — substring matching cross-assigns metrics on profiles
    /// whose DIDs share a prefix (e.g. `2248F9` / `224845` / `22480D` on the Mach-E).
    private func matchesCommand(_ target: String?, currentCommand: String) -> Bool {
        guard let target = target, !target.isEmpty else { return false }
        return target.replacingOccurrences(of: " ", with: "").uppercased()
            == currentCommand.replacingOccurrences(of: " ", with: "").uppercased()
    }

    private func extractBytes(from hex: String, command: String) -> [UInt8] {
        var clean = hex.uppercased()
        // Strip out positive response echo prefix (e.g. 62 01 01 or 62 1E 3B) if present
        let cleanCmd = command.replacingOccurrences(of: " ", with: "").uppercased()
        if cleanCmd.starts(with: "22") && cleanCmd.count >= 6 {
            let did = String(cleanCmd.dropFirst(2).prefix(4))
            let marker = "62" + did
            if let r = clean.range(of: marker) {
                clean = String(clean[r.upperBound...])
            }
        }

        var result: [UInt8] = []
        var index = clean.startIndex
        while clean.distance(from: index, to: clean.endIndex) >= 2 {
            let next = clean.index(index, offsetBy: 2)
            if let b = UInt8(clean[index..<next], radix: 16) {
                result.append(b)
            }
            index = next
        }
        return result
    }

    /// Evaluates ABRP byte math expressions like `((Signed(K)*256)+L)/10`, `((A<<8)+B)*0.01`,
    /// `1.12*A/2.5-7.16`, `INT16(A:B)*0.1`, `{j:1}`, and two-letter spreadsheet-column tokens
    /// (`ag`, `aa`, `ae`, ...) that address bytes 26 and beyond.
    private func evaluate(equation: String, bytes: [UInt8]) -> Double? {
        var expr = equation.trimmingCharacters(in: .whitespacesAndNewlines)
        if expr.isEmpty { return nil }

        // 1. INT16 pre-pass: INT16(hi:lo) -> ((Signed(hi)*256)+lo)
        if let int16Regex = try? NSRegularExpression(pattern: "(?i)INT16\\(([A-Za-z]{1,2}):([A-Za-z]{1,2})\\)") {
            expr = int16Regex.stringByReplacingMatches(
                in: expr, range: NSRange(expr.startIndex..., in: expr),
                withTemplate: "((Signed($1)*256)+$2)")
        }

        // 2. Bit tokens: {token:bit} -> 1 or 0, via byteIndex(forToken:).
        while let bitRange = expr.range(of: "\\{([A-Za-z]{1,2}):([0-9]+)\\}", options: .regularExpression) {
            let token = String(expr[bitRange])
            let inner = token.dropFirst().dropLast() // "token:bit"
            let parts = inner.split(separator: ":")
            guard parts.count == 2,
                  let byteIdx = Self.byteIndex(forToken: String(parts[0])),
                  let bitIdx = Int(parts[1]),
                  byteIdx < bytes.count else { return nil }
            let isSet = (bytes[byteIdx] & (1 << bitIdx)) != 0
            expr.replaceSubrange(bitRange, with: isSet ? "1" : "0")
        }

        // 3. Boolean folding: !1/!0, then && -> *, || -> +.
        var previous = ""
        while previous != expr {
            previous = expr
            expr = expr.replacingOccurrences(of: "!1", with: "0")
            expr = expr.replacingOccurrences(of: "!0", with: "1")
        }
        expr = expr.replacingOccurrences(of: "&&", with: "*")
        expr = expr.replacingOccurrences(of: "||", with: "+")

        // 4. Signed(token) -> signed integer value, via byteIndex(forToken:).
        if let signedRegex = try? NSRegularExpression(pattern: "(?i)signed\\(([a-z]{1,2})\\)") {
            while let match = signedRegex.firstMatch(in: expr, range: NSRange(expr.startIndex..., in: expr)),
                  let charRange = Range(match.range(at: 1), in: expr) {
                guard let idx = Self.byteIndex(forToken: String(expr[charRange])), idx < bytes.count else { return nil }
                let signedVal = Double(Int8(bitPattern: bytes[idx]))
                expr = (expr as NSString).replacingCharacters(in: match.range, with: "(\(signedVal))")
            }
        }

        // 5. Byte-letter substitution: single/two-letter tokens -> their UInt8 value.
        // Loop with firstMatch since replacement offsets shift; the parenthesized numeric
        // replacement never re-matches `\b[A-Za-z]{1,2}\b`, so this always terminates.
        if let tokenRegex = try? NSRegularExpression(pattern: "\\b[A-Za-z]{1,2}\\b") {
            while let match = tokenRegex.firstMatch(in: expr, range: NSRange(expr.startIndex..., in: expr)),
                  let tokenRange = Range(match.range, in: expr) {
                let token = String(expr[tokenRange])
                guard let idx = Self.byteIndex(forToken: token), idx < bytes.count else { return nil }
                let numStr = "(\(Double(bytes[idx])))"
                expr = (expr as NSString).replacingCharacters(in: match.range, with: numStr)
            }
        }

        // Replace bitshifts `<<` with power-of-2 multiplications
        expr = expr.replacingOccurrences(of: "<<8", with: "*256")
        expr = expr.replacingOccurrences(of: "<<16", with: "*65536")
        expr = expr.replacingOccurrences(of: "<<32", with: "*4294967296")

        // Evaluate mathematical expression using NSExpression
        let cleanExpr = expr.replacingOccurrences(of: "--", with: "+")

        // ponytail: NSExpression(format:) raises an *uncatchable* ObjC exception on
        // anything that isn't a well-formed expression. Reject non-arithmetic input here
        // rather than crash the app mid-drive.
        // Upgrade path: a real tokenizer if the ABRP grammar grows past byte math.
        guard cleanExpr.range(of: "^[0-9.+*/() -]+$", options: .regularExpression) != nil else { return nil }

        let nsExpr = NSExpression(format: cleanExpr)
        if let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber {
            return result.doubleValue
        }

        return nil
    }

    /// A..Z (case-insensitive) = 0..25, aa..az = 26..51, ba.. = 52.. (spreadsheet columns).
    static func byteIndex(forToken token: String) -> Int? {
        let chars = token.uppercased().compactMap { $0.asciiValue }.map { Int($0) - 65 }
        guard chars.allSatisfy({ (0..<26).contains($0) }) else { return nil }
        switch chars.count {
        case 1: return chars[0]
        case 2: return (chars[0] + 1) * 26 + chars[1]
        default: return nil
        }
    }
}

public final class ABRPProfileLoader {
    public static let shared = ABRPProfileLoader()

    private init() {}

    public static func loadProfile(filename: String, name: String = "Community Profile", capacityKWh: Double = 75.0) -> ABRPGenericVehicleProfile? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        let baseName = (filename as NSString).deletingPathExtension
        if let url = bundle.url(forResource: baseName, withExtension: "json", subdirectory: "abrp_pids") ??
                     bundle.url(forResource: baseName, withExtension: "json") ??
                     bundle.url(forResource: baseName, withExtension: "json", subdirectory: "Seed/abrp_pids") {
            if let data = try? Data(contentsOf: url),
               let def = try? JSONDecoder().decode(ABRPProfileDefinition.self, from: data) {
                return ABRPGenericVehicleProfile(name: name, capacityKWh: capacityKWh, definition: def)
            }
        }
        return nil
    }

    public static func loadBundledProfiles() -> [ABRPGenericVehicleProfile] {
        var profiles: [ABRPGenericVehicleProfile] = []
        
        let knownFiles: [(name: String, filename: String, capacity: Double)] = [
            ("Ford Mustang Mach-E", "ford_MachE.json", 91.0),
            ("Hyundai IONIQ 5 / Kia EV6", "hkmc_Ioniq5.json", 77.4),
            ("Hyundai / Kia (2019+)", "hkmc_hkmc2019.json", 64.0),
            ("Hyundai / Kia (2017)", "hkmc_hkmc2017.json", 28.0),
            ("Volkswagen ID.3 / ID.4 / MEB", "volkswagen_MEB.json", 77.0),
            ("Volkswagen e-Golf", "volkswagen_eGolf.json", 35.8),
            ("Volkswagen e-Up!", "volkswagen_eUP.json", 32.3),
            ("Mini Cooper SE", "Mini_MiniCooperSE.json", 28.9),
            ("Renault Zoe (ZE50)", "renault_zoe2.json", 52.0),
            ("Renault Zoe (ZE40)", "renault_zoe.json", 41.0),
            ("MG ZS EV", "mg_mgzsev.json", 68.3),
            ("Jaguar I-Pace (2021+)", "jaguar_ipace2021.json", 84.7),
            ("Jaguar I-Pace (2019)", "jaguar_ipace2019.json", 84.7),
            ("Chevrolet Bolt EV (2019+)", "gmc_bolt19.json", 66.0),
            ("Chevrolet Bolt EV (2017)", "gmc_bolt17.json", 60.0),
            ("Honda e:Ny1", "honda_eny1.json", 68.8),
            ("Aiways U5", "aiways_u5.json", 63.0),
            ("BYD Atto 3 / Yuan Plus", "byd_atto3.json", 60.5),
            ("BMW i3", "bmw_i3.json", 37.9),
            ("Deepal S05", "deepal_s05.json", 56.1)
        ]

        for item in knownFiles {
            if let profile = loadProfile(filename: item.filename, name: item.name, capacityKWh: item.capacity) {
                profiles.append(profile)
            }
        }

        return profiles
    }
}
