import Foundation

/// Generic SAE J1979 EV fallback profile. Byte-for-byte the same PID set and decode math
/// as `GenericOBD2Profile` (only the catalog name and `isElectricVehicle` flag differ), so
/// this simply wraps that implementation rather than duplicating it.
public struct GenericEVProfile: VehicleProfile {
    private let core = GenericOBD2Profile(vehicleName: "Generic EV (SAE J1979)", isElectricVehicle: true)

    public var vehicleName: String { core.vehicleName }
    public var isElectricVehicle: Bool { core.isElectricVehicle }
    public var batteryUsableCapacityKWh: Double { core.batteryUsableCapacityKWh }
    public var initializationCommands: [String] { core.initializationCommands }
    public var pollingCommands: [String] { core.pollingCommands }
    public var supportedMetrics: Set<TelemetryMetric> { core.supportedMetrics }

    public init() {}

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        core.parseResponse(command: command, rawResponse: rawResponse)
    }
}
