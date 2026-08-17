import Foundation

public struct MercedesEQA250Profile: VehicleProfile {
    public let vehicleName = "Mercedes-Benz EQA 250 (2021)"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh: Double = 66.5
    public let grossCapacityKWh: Double = 69.7

    private let isoParser = ISO15765Parser()

    public var initializationCommands: [String] {
        [
            "AT Z",            // Reset ELM327
            "AT E0",           // Echo Off
            "AT L0",           // Linefeed Off
            "AT S1",           // Spaces On (required by the space-delimited ISO-TP token parser)
            "AT H1",           // Headers On (for CAN ID recognition)
            "AT CAF 1",        // CAN Auto Formatting
            "AT SP 7",         // Force ISO 15765-4 CAN (29-bit ID, 500 kbps)
            "AT CP 18",        // 29-bit CAN Priority
            "AT ST FF",        // ELM response timeout ~1.02s
            "ATCRA 18DAF159",  // CAN Receive filter for BMS
            "AT SH 18DA59F1",  // Physical addressing: tester (F1) -> BMS ECU (0x59)
            "AT FCSH 18DA59F1",
            "AT FCSD 300000",
            "AT FCSM 1"
        ]
    }

    public var pollingCommands: [String] {
        [
            "ATCRA 18DAF159",
            "AT SH 18DA59F1",
            "22010A",         // BMS pack voltage (0.1V resolution)
            "220210",         // Customer SOC (0.004% resolution)
            "22010B",         // BMS pack current (signed, 0.1A resolution)
            "22010C"          // BMS battery temperature
        ]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        [.soc, .packVoltage, .power, .batteryTemp, .packCurrent]
    }

    public init() {}

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let cleanHex = isoParser.assembleISOTPPayload(rawResponse)
        
        switch command {
        case "22010A", "22 01 0A": // BMS pack voltage (ECU 0x59)
            if let bytes = extractBytes(from: cleanHex, header: "62010A", count: 2) {
                let voltage = (Double(bytes[0]) * 256.0 + Double(bytes[1])) * 0.1
                return .packVoltage(voltage)
            }
            return nil

        case "220210", "22 02 10": // BMS customer SOC (ECU 0x59)
            // Capture: 62 02 10 04 00 00 3C AC ... => 0x3CAC / 250 = 62.128%
            if let bytes = extractBytes(from: cleanHex, header: "620210", count: 5), bytes[0] == 0x04 {
                let raw = UInt32(bytes[1]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 8 | UInt32(bytes[4])
                let soc = Double(raw) / 250.0
                if (0...100).contains(soc) {
                    return .soc(soc)
                }
            }
            return nil

        case "22010B", "22 01 0B": // BMS pack current (ECU 0x59)
            if let bytes = extractBytes(from: cleanHex, header: "62010B", count: 2) {
                let rawInt16 = Int16(Int8(bitPattern: bytes[0])) * 256 + Int16(bytes[1])
                let current = Double(rawInt16) * 0.1
                let voltage = 390.0
                return .power(voltage: voltage, current: current, powerKW: (voltage * current) / 1000.0)
            }
            return nil

        case "22010C", "22 01 0C": // BMS pack temperature
            if let bytes = extractBytes(from: cleanHex, header: "62010C", count: 1) {
                let temp = Double(Int(bytes[0]) - 40)
                return .batteryTemp(min: temp, max: temp, avg: temp)
            }
            return nil

        default:
            return nil
        }
    }

    private func extractBytes(from hex: String, header: String, count: Int) -> [UInt8]? {
        guard let range = hex.range(of: header) else { return nil }
        let afterHeader = String(hex[range.upperBound...])
        guard afterHeader.count >= count * 2 else { return nil }
        var bytes: [UInt8] = []
        for i in 0..<count {
            let start = afterHeader.index(afterHeader.startIndex, offsetBy: i * 2)
            let end = afterHeader.index(start, offsetBy: 2)
            let byteStr = String(afterHeader[start..<end])
            if let b = UInt8(byteStr, radix: 16) {
                bytes.append(b)
            }
        }
        return bytes.count == count ? bytes : nil
    }
}
