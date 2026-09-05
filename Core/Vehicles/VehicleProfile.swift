import Foundation

public protocol VehicleProfile: Sendable {
    var vehicleName: String { get }
    var isElectricVehicle: Bool { get }
    var batteryUsableCapacityKWh: Double { get }
    var initializationCommands: [String] { get }
    var pollingCommands: [String] { get }
    var supportedMetrics: Set<TelemetryMetric> { get }

    /// Manufacturer-published full-charge range (e.g. WLTP), used as a conservative
    /// estimate basis for the dashboard's "estimated range" SoC dial toggle. Defaults to
    /// `Self.defaultEstimatedFullRangeKm` when a profile doesn't know its vehicle's range.
    var estimatedFullRangeKm: Double { get }

    func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate?
}

extension VehicleProfile {
    /// Fallback used by profiles (generic OBD-II, unrecognized ABRP vehicles, ...) that have
    /// no published range figure to report.
    public static var defaultEstimatedFullRangeKm: Double { 400.0 }

    public var estimatedFullRangeKm: Double { Self.defaultEstimatedFullRangeKm }
}
