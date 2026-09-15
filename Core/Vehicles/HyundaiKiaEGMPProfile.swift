import Foundation

/// Community OBD profile for 2022–2024 Hyundai IONIQ 5 and Kia EV6.
/// Commands and byte formulas are from iternio/ev-obd-pids (Apache-2.0),
/// hkmc/Ioniq5.json. Validate against the connected vehicle before treating
/// this as a dealer-grade diagnostic profile.
public struct HyundaiKiaEGMPProfile: VehicleProfile {
    public let vehicleName = "Hyundai/Kia E-GMP"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh: Double = 77.4
    /// Conservative WLTP range across IONIQ 5 / EV6 trims.
    public let estimatedFullRangeKm: Double? = 460.0

    private let isoParser = ISO15765Parser()

    public var initializationCommands: [String] {
        ["AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT ST FF", "AT SP 6"]
    }

    public var pollingCommands: [String] {
        ["ATCRA7EC", "220101", "220105"]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        // `parseResponses` emits multiple updates per reply: pack power (V/A/kW) plus the
        // 12 V aux reading from 220101, and SOC plus SOH from 220105. Pack temperature is
        // deliberately not emitted — the only source entries in hkmc_Ioniq5.json for it are
        // underscore-disabled (`_Bat_Min_Temp`/`_Bat_Max_Temp`) and collide with the
        // pack-voltage bytes used here, so it can't be cross-checked against a bundled JSON.
        [.power, .packVoltage, .packCurrent, .soc, .soh, .aux12V]
    }

    public init() {}

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let hex = isoParser.assembleISOTPPayload(rawResponse)
        guard let payload = hex.hexBytes(after: command == "220101" ? "620101" : "620105") else { return nil }

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

    /// Emits the primary metric from `parseResponse` plus any secondary metric decodable
    /// from the same payload: 12 V aux voltage alongside pack power, and SOH alongside SOC.
    public func parseResponses(command: String, rawResponse: String) -> [TelemetryUpdate] {
        guard let base = parseResponse(command: command, rawResponse: rawResponse) else { return [] }
        guard let payload = isoParser.assembleISOTPPayload(rawResponse)
            .hexBytes(after: command == "220101" ? "620101" : "620105") else { return [base] }

        switch command {
        case "220101":
            // ABRP: _Aux_Bat_Voltage = ae*0.1 (byte 30).
            guard payload.count > 30 else { return [base] }
            return [base, .aux12V(Double(payload[30]) * 0.1)]

        case "220105":
            // ABRP: SOH = ((aa<<8)+ab)/10 (bytes 26/27).
            guard payload.count > 32 else { return [base] }
            let soh = Double(UInt16(payload[26]) << 8 | UInt16(payload[27])) / 10
            guard (0...100).contains(soh) else { return [base] }
            return [base, .soh(soh)]

        default:
            return [base]
        }
    }
}
