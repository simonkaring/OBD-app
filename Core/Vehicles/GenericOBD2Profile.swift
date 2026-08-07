import Foundation

public struct GenericOBD2Profile: VehicleProfile {
    public let vehicleName = "Generic SAE J1979 OBD-II"
    public let isElectricVehicle = false
    public let batteryUsableCapacityKWh: Double = 0.0

    private let isoParser = ISO15765Parser()

    public var initializationCommands: [String] {
        [
            "AT Z",
            "AT E0",
            "AT L0",
            "AT S0",
            "AT SP 0" // Auto-detect protocol
        ]
    }

    public var pollingCommands: [String] {
        [
            "010D", // Vehicle Speed
            "010C", // Engine RPM
            "0105", // Engine Coolant Temp
            "0142"  // Control Module Voltage (12V)
        ]
    }

    public init() {}

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let cleanHex = isoParser.assembleISOTPPayload(rawResponse)

        switch command {
        case "010D", "01 0D":
            guard let speedByte = extractByte(from: cleanHex, header: "410D") else { return nil }
            return .speed(Double(speedByte))

        case "010C", "01 0C":
            guard let bytes = extractBytes(from: cleanHex, header: "410C", count: 2) else { return nil }
            let rpm = (Double(bytes[0]) * 256.0 + Double(bytes[1])) / 4.0
            return .motorStats(rpm: rpm, torque: 0.0)

        case "0142", "01 42":
            guard let bytes = extractBytes(from: cleanHex, header: "4142", count: 2) else { return nil }
            let volts = (Double(bytes[0]) * 256.0 + Double(bytes[1])) / 1000.0
            return .aux12V(volts)

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
