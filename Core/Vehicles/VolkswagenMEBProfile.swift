import Foundation

/// Community OBD profile for Volkswagen Group MEB platform vehicles:
/// - Volkswagen ID.3, ID.4, ID.5, ID.7, ID.Buzz
/// - Škoda Enyaq iV
/// - Cupra Born, Cupra Tavascan
/// - Audi Q4 e-tron
///
/// Formulas and initialization sequence derived from `iternio/ev-obd-pids` (volkswagen/MEB.json).
public struct VolkswagenMEBProfile: VehicleProfile {
    public let vehicleName = "Volkswagen MEB (ID.3 / ID.4 / ID.Buzz)"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh: Double = 77.0

    private let isoParser = ISO15765Parser()

    public var initializationCommands: [String] {
        [
            "AT Z",
            "AT E0",
            "AT L0",
            "AT S1",
            "AT H1",
            "AT SP 7",
            "AT BI",
            "AT SH FC007B",
            "AT CP 17",
            "AT CAF 0",
            "AT CF 17FE7",
            "AT CRA 17FE007B"
        ]
    }

    public var pollingCommands: [String] {
        [
            "03221E3D55555555", // HV Current
            "03221E3B55555555", // HV Voltage
            "0322028C55555555", // Display SOC
            "0322744855555555"  // Charging status
        ]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        // No DID in `pollingCommands` reports pack temperature, so `.batteryTemp` is
        // deliberately not advertised.
        [.power, .soc, .packVoltage, .packCurrent]
    }

    public init() {}

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        // Byte offsets are positional, so multi-frame replies must be reassembled first —
        // raw text keeps CAN IDs and ISO-TP PCI bytes interleaved with the data.
        let hex = isoParser.assembleISOTPPayload(rawResponse)

        switch command {
        case "03221E3D55555555":
            // Current DID 0x1E3D: response contains 62 1E 3D [A B C D]
            guard let payload = extractPayload(after: "621E3D", in: hex), payload.count >= 4 else { return nil }
            let a = Double(payload[0])
            let b = Double(payload[1])
            let c = Double(payload[2])
            let d = Double(payload[3])
            let rawVal = (a * 16_777_216.0) + (b * 65_536.0) + (c * 256.0) + d
            let currentA = ((rawVal - 150_000.0) / 100.0) * -1.0
            // Emit standalone current so the manager pairs it with the pack voltage read
            // from DID 0x1E3B, rather than a fabricated 400 V nominal that would also
            // overwrite the real measured voltage in the snapshot.
            return .packCurrent(currentA)

        case "03221E3B55555555":
            // Voltage DID 0x1E3B: response contains 62 1E 3B [A B]
            guard let payload = extractPayload(after: "621E3B", in: hex), payload.count >= 2 else { return nil }
            let a = Double(payload[0])
            let b = Double(payload[1])
            let voltageV = ((a * 256.0) + b) / 4.0
            return .packVoltage(voltageV)

        case "0322028C55555555":
            // Display SOC DID 0x028C: response contains 62 02 8C [A]
            guard let payload = extractPayload(after: "62028C", in: hex), payload.count >= 1 else { return nil }
            let a = Double(payload[0])
            let soc = (1.12 * a / 2.5) - 7.16
            let clampedSOC = min(100.0, max(0.0, soc))
            return .soc(clampedSOC)

        case "0322744855555555":
            // Charging status DID 0x7448: bit 2 of byte A indicates charging
            guard let payload = extractPayload(after: "627448", in: hex), payload.count >= 1 else { return nil }
            let isCharging = (payload[0] & 0x04) != 0
            let isDCFC = (payload[0] & 0x02) != 0 && isCharging
            // The DID is a status bitfield, not a power reading — report an unknown rate
            // while charging instead of a fabricated 50 kW.
            return .chargingStats(kwRate: isCharging ? nil : 0.0, acOrDc: isDCFC ? "DC" : "AC")

        default:
            return nil
        }
    }

    private func extractPayload(after marker: String, in hex: String) -> [UInt8]? {
        guard let range = hex.range(of: marker) else { return nil }
        let suffix = String(hex[range.upperBound...])
        guard suffix.count >= 2 else { return nil }
        var bytes: [UInt8] = []
        var index = suffix.startIndex
        while suffix.distance(from: index, to: suffix.endIndex) >= 2 {
            let next = suffix.index(index, offsetBy: 2)
            if let byte = UInt8(suffix[index..<next], radix: 16) {
                bytes.append(byte)
            }
            index = next
        }
        return bytes
    }
}
