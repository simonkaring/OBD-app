import Foundation

public struct MercedesEQA250Profile: VehicleProfile {
    public let vehicleName = "Mercedes-Benz EQA 250 (2021)"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh: Double = 66.5
    public let grossCapacityKWh: Double = 69.7

    private let isoParser = ISO15765Parser()

    public var initializationCommands: [String] {
        [
            "AT Z",       // Reset ELM327
            "AT E0",      // Echo Off
            "AT L0",      // Linefeed Off
            "AT S0",      // Spaces Off
            "AT H1",      // Headers On (for CAN ID recognition)
            "AT CAF 1",   // CAN Auto Formatting
            "AT SP 6",    // ISO 15765-4 CAN 11-bit 500k baud
            "AT AL",      // Allow Long messages
            "AT SH 7E4"   // Set Header to BMS (Battery Management System)
        ]
    }

    public var pollingCommands: [String] {
        [
            "AT SH 7E4", // Select BMS ECU Header
            "220101",    // State of Charge (SOC %)
            "220102",    // State of Health (SOH %)
            "220105",    // Pack Voltage & Amperage
            "220110",    // Pack & Coolant Temperatures
            "220120",    // 12V Aux Battery
            "AT SH 7E0", // Select Powertrain ECU Header
            "010D",      // Vehicle Speed
            "220301"     // Motor RPM & Torque
        ]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        [.speed, .power, .soc, .soh, .batteryTemp, .aux12V, .motorRpm, .motorTorque]
    }

    public init() {}

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let cleanHex = isoParser.assembleISOTPPayload(rawResponse)
        
        switch command {
        case "010D", "01 0D":
            // Standard SAE speed byte
            guard let speedByte = extractByte(from: cleanHex, header: "410D") else { return nil }
            return .speed(Double(speedByte))

        case "220101": // SOC
            guard let byte = extractByte(from: cleanHex, header: "620101") else { return nil }
            let soc = Double(byte) * 0.5
            return .soc(min(100.0, max(0.0, soc)))

        case "220102": // SOH
            guard let byte = extractByte(from: cleanHex, header: "620102") else { return nil }
            let soh = Double(byte) * 0.5
            return .soh(min(100.0, max(0.0, soh)))

        case "220105": // Voltage & Current -> kW
            // Format: 62 01 05 VV VV AA AA
            guard let bytes = extractBytes(from: cleanHex, header: "620105", count: 4) else { return nil }
            let voltage = (Double(bytes[0]) * 256.0 + Double(bytes[1])) * 0.1
            let rawCurrentInt = Int16(bitPattern: UInt16(bytes[2]) << 8 | UInt16(bytes[3]))
            let current = Double(rawCurrentInt) * 0.1
            let powerKW = (voltage * current) / 1000.0
            return .power(voltage: voltage, current: current, powerKW: powerKW)

        case "220110": // Battery Temp
            guard let bytes = extractBytes(from: cleanHex, header: "620110", count: 2) else { return nil }
            let minTemp = Double(bytes[0]) - 40.0
            let maxTemp = Double(bytes[1]) - 40.0
            return .batteryTemp(min: minTemp, max: maxTemp, avg: (minTemp + maxTemp) / 2.0)

        case "220120": // 12V Aux
            guard let bytes = extractBytes(from: cleanHex, header: "620120", count: 2) else { return nil }
            let volts = (Double(bytes[0]) * 256.0 + Double(bytes[1])) / 1000.0
            return .aux12V(volts)

        case "220301": // Motor RPM & Torque
            guard let bytes = extractBytes(from: cleanHex, header: "620301", count: 4) else { return nil }
            let rpm = Double(bytes[0]) * 256.0 + Double(bytes[1])
            let torque = Double(bytes[2]) * 256.0 + Double(bytes[3]) - 500.0
            return .motorStats(rpm: rpm, torque: torque)

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
