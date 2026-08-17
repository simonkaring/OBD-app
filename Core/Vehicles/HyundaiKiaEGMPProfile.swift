import Foundation

/// Community OBD profile for 2022–2024 Hyundai IONIQ 5 and Kia EV6.
/// Commands and byte formulas are from iternio/ev-obd-pids (Apache-2.0),
/// hkmc/Ioniq5.json. Validate against the connected vehicle before treating
/// this as a dealer-grade diagnostic profile.
public struct HyundaiKiaEGMPProfile: VehicleProfile {
    public let vehicleName = "Hyundai/Kia E-GMP"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh: Double = 77.4

    private let isoParser = ISO15765Parser()

    public var initializationCommands: [String] {
        ["AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT ST FF", "AT SP 6"]
    }

    public var pollingCommands: [String] {
        ["ATCRA7EC", "220101", "220105"]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        [.power, .soc, .soh, .batteryTemp, .aux12V]
    }

    public init() {}

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let hex = isoParser.assembleISOTPPayload(rawResponse)
        guard let payload = bytes(after: command == "220101" ? "620101" : "620105", in: hex) else { return nil }

        switch command {
        case "220101":
            // ABRP: current=((Signed(K)*256)+L)/10, voltage=((N<<8)+O)/10.
            guard payload.count > 14 else { return nil }
            let currentRaw = Int16(bitPattern: UInt16(payload[10]) << 8 | UInt16(payload[11]))
            let current = Double(currentRaw) / 10
            let voltage = Double(UInt16(payload[13]) << 8 | UInt16(payload[14])) / 10
            return .power(voltage: voltage, current: current, powerKW: voltage * current / 1_000)

        case "220105":
            // ABRP: SOC=ag/2, SOH=((aa<<8)+ab)/10. SOC is the priority
            // update; SOH remains available through the generic profile path.
            guard payload.count > 32 else { return nil }
            return .soc(Double(payload[32]) / 2)

        default:
            return nil
        }
    }

    private func bytes(after header: String, in hex: String) -> [UInt8]? {
        guard let range = hex.range(of: header) else { return nil }
        let suffix = String(hex[range.upperBound...])
        guard suffix.count.isMultiple(of: 2) else { return nil }
        return stride(from: 0, to: suffix.count, by: 2).compactMap {
            UInt8(String(suffix.dropFirst($0).prefix(2)), radix: 16)
        }
    }
}
