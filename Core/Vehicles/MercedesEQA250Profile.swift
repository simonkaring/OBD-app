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
            "ATCRA 18DAF129",  // CAN Receive filter for Inverter
            "AT SH 18DA29F1",  // Physical addressing: tester (F1) -> Inverter ECU (0x29)
            "AT FCSH 18DA29F1",
            "AT FCSD 300000",
            "AT FCSM 1"
        ]
    }

    public var pollingCommands: [String] {
        [
            "ATCRA 18DAF129",
            "AT SH 18DA29F1",
            "22012F",         // Inverter State of Charge (0.1% resolution)
            "22010A",         // Inverter Pack Voltage (0.1V resolution)
            "ATCRA 18DAF159",
            "AT SH 18DA59F1",
            "22010A",         // BMS Pack Voltage (0.1V resolution)
            "22010C"          // BMS Status & Remaining Capacity
        ]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        [.soc, .packVoltage, .power, .packCurrent]
    }

    public init() {}

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let cleanHex = isoParser.assembleISOTPPayload(rawResponse)
        
        switch command {
        case "22012F", "22 01 2F": // Inverter State of Charge (ECU 0x29)
            if let bytes = extractBytes(from: cleanHex, header: "62012F", count: 2) {
                let soc = (Double(bytes[0]) * 256.0 + Double(bytes[1])) * 0.1
                if soc >= 0.0 && soc <= 100.0 {
                    return .soc(soc)
                }
            } else if let byte = extractByte(from: cleanHex, header: "62012F") {
                let soc = Double(byte) * 0.5
                if soc >= 0.0 && soc <= 100.0 {
                    return .soc(soc)
                }
            }
            return nil

        case "22010A", "22 01 0A": // Pack Voltage (ECU 0x29 & 0x59)
            if let bytes = extractBytes(from: cleanHex, header: "62010A", count: 4) {
                let voltage = (Double(bytes[0]) * 256.0 + Double(bytes[1])) * 0.1
                let rawCurrentInt = Int16(bitPattern: UInt16(bytes[2]) << 8 | UInt16(bytes[3]))
                let current = Double(rawCurrentInt) * 0.1
                let powerKW = (voltage * current) / 1000.0
                return .power(voltage: voltage, current: current, powerKW: powerKW)
            } else if let bytes = extractBytes(from: cleanHex, header: "62010A", count: 2) {
                let voltage = (Double(bytes[0]) * 256.0 + Double(bytes[1])) * 0.1
                return .packVoltage(voltage)
            }
            return nil

        case "22010C", "22 01 0C": // BMS Status & SOH (ECU 0x59)
            if let bytes = extractBytes(from: cleanHex, header: "62010C", count: 3) {
                // Byte 0: status flags (0x08 indicates contactors closed / active)
                // Byte 1 & 2: remaining capacity or SOH
                let status = bytes[0]
                if status == 0x08 {
                    // Contactor closed / active telemetry
                }
            }
            return nil

        case "220101", "22 01 01": // Fallback BMS SOC (ECU 0x59)
            if let bytes = extractBytes(from: cleanHex, header: "620101", count: 2) {
                let val = (Double(bytes[0]) * 256.0 + Double(bytes[1])) * 0.1
                if val >= 0.0 && val <= 100.0 {
                    return .soc(val)
                }
            }
            return nil

        case "220102", "22 01 02": // Fallback BMS Real SOC (ECU 0x59)
            if let bytes = extractBytes(from: cleanHex, header: "620102", count: 2) {
                let val = (Double(bytes[0]) * 256.0 + Double(bytes[1])) * 0.1
                if val >= 0.0 && val <= 100.0 {
                    return .soc(val)
                }
            }
            return nil

        default:
            return nil
        }
    }

    private func extractByte(from hex: String, header: String) -> UInt8? {
        guard let range = hex.range(of: header) else { return nil }
        let afterHeader = String(hex[range.upperBound...])
        guard afterHeader.count >= 2 else { return nil }
        let byteStr = String(afterHeader.prefix(2))
        return UInt8(byteStr, radix: 16)
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
