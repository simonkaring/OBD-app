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
        if definition.voltage != nil || definition.current != nil { set.insert(.power); set.insert(.packVoltage) }
        if definition.soh != nil { set.insert(.soh) }
        if definition.battTemp != nil { set.insert(.batteryTemp) }
        if definition.speed != nil { set.insert(.speed) }
        return set
    }

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let hex = isoParser.cleanELMResponse(rawResponse).replacingOccurrences(of: " ", with: "")
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
                return .power(voltage: 400.0, current: a, powerKW: (400.0 * a) / 1_000.0)
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

    private func matchesCommand(_ target: String?, currentCommand: String) -> Bool {
        guard let target = target, !target.isEmpty else { return true }
        let cleanTarget = target.replacingOccurrences(of: " ", with: "").uppercased()
        let cleanCurrent = currentCommand.replacingOccurrences(of: " ", with: "").uppercased()
        return cleanTarget == cleanCurrent || cleanCurrent.contains(cleanTarget) || cleanTarget.contains(cleanCurrent)
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

    /// Evaluates ABRP byte math expressions like `((Signed(K)*256)+L)/10`, `((A<<8)+B)*0.01`, `1.12*A/2.5-7.16`.
    private func evaluate(equation: String, bytes: [UInt8]) -> Double? {
        var expr = equation.trimmingCharacters(in: .whitespacesAndNewlines)
        if expr.isEmpty { return nil }

        // Fast path for simple known patterns
        // 1. Bit access: {A:2} or ({A:1}&&{A:2})
        if expr.contains("{") && bytes.count > 0 {
            if let bitRange = expr.range(of: "\\{[A-Za-z]:[0-9]+\\}", options: .regularExpression) {
                let token = String(expr[bitRange])
                let char = token.dropFirst(1).first ?? "A"
                let bitIdx = Int(String(token.dropFirst(3).dropLast(1))) ?? 0
                let byteIdx = byteIndex(for: char)
                if byteIdx < bytes.count {
                    let isSet = (bytes[byteIdx] & (1 << bitIdx)) != 0
                    return isSet ? 1.0 : 0.0
                }
            }
        }

        // Replace signed(X) with signed integer value
        let signedRegex = try? NSRegularExpression(pattern: "(?i)signed\\(([a-z]+)\\)")
        if let match = signedRegex?.firstMatch(in: expr, range: NSRange(expr.startIndex..., in: expr)) {
            if let charRange = Range(match.range(at: 1), in: expr) {
                let charName = String(expr[charRange])
                let idx = byteIndex(for: charName.first ?? "A")
                if idx < bytes.count {
                    let signedVal = Double(Int8(bitPattern: bytes[idx]))
                    expr = (expr as NSString).replacingCharacters(in: match.range, with: "\(signedVal)")
                }
            }
        }

        // Replace byte letters (A..Z, AA..AZ) with their UInt8 value
        for i in 0..<min(bytes.count, 26) {
            let letter = Character(UnicodeScalar(65 + i)!)
            let regex = try? NSRegularExpression(pattern: "\\b\(letter)\\b")
            let numStr = "\(Double(bytes[i]))"
            expr = regex?.stringByReplacingMatches(in: expr, range: NSRange(expr.startIndex..., in: expr), withTemplate: numStr) ?? expr
        }

        // Replace bitshifts `<<` with power-of-2 multiplications
        expr = expr.replacingOccurrences(of: "<<8", with: "*256")
        expr = expr.replacingOccurrences(of: "<<16", with: "*65536")
        expr = expr.replacingOccurrences(of: "<<32", with: "*4294967296")

        // Evaluate mathematical expression using NSExpression
        let cleanExpr = expr.replacingOccurrences(of: "--", with: "+")
        let nsExpr = NSExpression(format: cleanExpr)
        if let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber {
            return result.doubleValue
        }

        return nil
    }

    private func byteIndex(for char: Character) -> Int {
        let upper = String(char).uppercased().first ?? "A"
        let val = Int(upper.asciiValue ?? 65)
        return max(0, val - 65)
    }
}

public final class ABRPProfileLoader {
    public static let shared = ABRPProfileLoader()

    private init() {}

    public static func loadBundledProfiles() -> [ABRPGenericVehicleProfile] {
        var profiles: [ABRPGenericVehicleProfile] = []
        
        let knownFiles: [(name: String, filename: String, capacity: Double)] = [
            ("Ford Mustang Mach-E", "ford_MachE.json", 91.0),
            ("Hyundai IONIQ 5 / Kia EV6", "hkmc_Ioniq5.json", 77.4),
            ("Volkswagen ID.3 / ID.4 / MEB", "volkswagen_MEB.json", 77.0),
            ("Volkswagen e-Golf", "volkswagen_eGolf.json", 35.8),
            ("Volkswagen e-Up!", "volkswagen_eUP.json", 32.3),
            ("Mini Cooper SE", "Mini_MiniCooperSE.json", 28.9),
            ("Renault Zoe (ZE50)", "renault_zoe2.json", 52.0),
            ("MG ZS EV", "mg_mgzsev.json", 68.3),
            ("Jaguar I-Pace", "jaguar_ipace2021.json", 84.7)
        ]

        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        for item in knownFiles {
            let baseName = (item.filename as NSString).deletingPathExtension
            if let url = bundle.url(forResource: baseName, withExtension: "json", subdirectory: "abrp_pids") ??
                         bundle.url(forResource: baseName, withExtension: "json") {
                if let data = try? Data(contentsOf: url),
                   let def = try? JSONDecoder().decode(ABRPProfileDefinition.self, from: data) {
                    profiles.append(ABRPGenericVehicleProfile(name: item.name, capacityKWh: item.capacity, definition: def))
                }
            }
        }

        return profiles
    }
}
