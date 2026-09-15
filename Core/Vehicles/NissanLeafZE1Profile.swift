import Foundation

/// Community OBD profile for Nissan Leaf ZE1 (62 kWh, 2019+).
/// Poll PIDs and byte offsets are transcribed from the MIT-licensed
/// Open Vehicle Monitoring System 3 `vehicle_nissanleaf` component
/// (github.com/openvehicles/Open-Vehicle-Monitoring-System-3).
///
/// OVMS reads pack voltage/current by passively sniffing broadcast CAN
/// frame 0x1DB, which this app's request/response poll loop can't do —
/// only the two BMS "OBDIIGROUP" request/response PIDs (SOC, SOH) are
/// exposed here. Validate against the connected vehicle before treating
/// this as a dealer-grade diagnostic profile.
public struct NissanLeafZE1Profile: VehicleProfile {
    public let vehicleName = "Nissan Leaf (62 kWh, ZE1)"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh: Double = 56.0
    /// WLTP-rated full-charge range for the 62 kWh pack, conservative rounding.
    public let estimatedFullRangeKm: Double? = 385.0

    private let isoParser = ISO15765Parser()

    public var initializationCommands: [String] {
        ["AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT SP 5", "AT SH 79B", "AT CRA 7BB"]
    }

    public var pollingCommands: [String] {
        ["2101", "2161"]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        [.soc, .soh]
    }

    public init() {}

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let hex = isoParser.assembleISOTPPayload(rawResponse)

        switch command {
        case "2101":
            // Group 0x01 reply: SOC = (byte31<<16 | byte32<<8 | byte33) / 10000, in percent.
            guard let payload = hex.hexBytes(after: "6101"), payload.count > 33 else { return nil }
            let raw = (UInt32(payload[31]) << 16) | (UInt32(payload[32]) << 8) | UInt32(payload[33])
            return .soc(Double(raw) / 10_000.0)

        case "2161":
            // Group 0x61 reply: SOH = (byte2<<8 | byte3) / 100, in percent.
            guard let payload = hex.hexBytes(after: "6161"), payload.count > 3 else { return nil }
            let raw = (UInt16(payload[2]) << 8) | UInt16(payload[3])
            return .soh(Double(raw) / 100.0)

        default:
            return nil
        }
    }
}
