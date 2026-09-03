import Foundation

public struct GenericEVProfile: VehicleProfile {
    public let vehicleName = "Generic EV (SAE J1979)"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh: Double = 0.0

    private let isoParser = ISO15765Parser()

    public var initializationCommands: [String] {
        [
            "AT Z",
            "AT E0",
            "AT L0",
            "AT S1", // Spaces On (required by the space-delimited ISO-TP token parser)
            "AT SP 0" // Auto-detect protocol
        ]
    }

    public var pollingCommands: [String] {
        [
            "010D", // Vehicle Speed
            "010C", // Engine RPM
            "0105", // Engine Coolant Temp
            "0142", // Control Module Voltage (12V)
            "0104", // Calculated Engine Load
            "010F", // Intake Air Temp
            "0111", // Throttle Position
            "012F", // Fuel Level
            "015B", // Hybrid/EV Battery Pack Remaining Life (SAE J1979 standard EV SOC)
            "0146", // Ambient Air Temp
            "0110", // Mass Air Flow Rate
            "010B", // Intake Manifold Absolute Pressure
            "015C", // Engine Oil Temperature
            "010E", // Timing Advance
            "0133"  // Barometric Pressure
        ]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        [
            .speed, .motorRpm, .aux12V, .engineLoad, .coolantTemp, .intakeAirTemp, .throttlePosition, .fuelLevel, .soc,
            .ambientAirTemp, .maf, .manifoldPressure, .oilTemp, .timingAdvance, .barometricPressure
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

        case "0105", "01 05":
            guard let byte = extractByte(from: cleanHex, header: "4105") else { return nil }
            return .coolantTemp(Double(byte) - 40.0)

        case "0104", "01 04":
            guard let byte = extractByte(from: cleanHex, header: "4104") else { return nil }
            return .engineLoad(Double(byte) * 100.0 / 255.0)

        case "010F", "01 0F":
            guard let byte = extractByte(from: cleanHex, header: "410F") else { return nil }
            return .intakeAirTemp(Double(byte) - 40.0)

        case "0111", "01 11":
            guard let byte = extractByte(from: cleanHex, header: "4111") else { return nil }
            return .throttlePosition(Double(byte) * 100.0 / 255.0)

        case "012F", "01 2F":
            guard let byte = extractByte(from: cleanHex, header: "412F") else { return nil }
            return .fuelLevel(Double(byte) * 100.0 / 255.0)

        case "015B", "01 5B":
            guard let byte = extractByte(from: cleanHex, header: "415B") else { return nil }
            return .soc(Double(byte) * 100.0 / 255.0)

        case "0146", "01 46":
            guard let byte = extractByte(from: cleanHex, header: "4146") else { return nil }
            return .ambientAirTemp(Double(byte) - 40.0)

        case "0110", "01 10":
            guard let bytes = extractBytes(from: cleanHex, header: "4110", count: 2) else { return nil }
            let maf = (Double(bytes[0]) * 256.0 + Double(bytes[1])) / 100.0
            return .maf(maf)

        case "010B", "01 0B":
            guard let byte = extractByte(from: cleanHex, header: "410B") else { return nil }
            return .manifoldPressure(Double(byte))

        case "015C", "01 5C":
            guard let byte = extractByte(from: cleanHex, header: "415C") else { return nil }
            return .oilTemp(Double(byte) - 40.0)

        case "010E", "01 0E":
            guard let byte = extractByte(from: cleanHex, header: "410E") else { return nil }
            return .timingAdvance(Double(byte) / 2.0 - 64.0)

        case "0133", "01 33":
            guard let byte = extractByte(from: cleanHex, header: "4133") else { return nil }
            return .barometricPressure(Double(byte))

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
