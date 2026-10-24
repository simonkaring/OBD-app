import Foundation

public protocol VehicleProfile: Sendable {
    var vehicleName: String { get }
    var isElectricVehicle: Bool { get }
    var batteryUsableCapacityKWh: Double { get }
    var initializationCommands: [String] { get }
    var pollingCommands: [String] { get }
    var supportedMetrics: Set<TelemetryMetric> { get }

    /// Manufacturer-published full-charge range (e.g. WLTP), used as a conservative
    /// estimate basis for the dashboard's "estimated range" SoC dial toggle. `nil` indicates
    /// the profile doesn't have a known range (generic OBD-II, unrecognized ABRP vehicles, etc.).
    var estimatedFullRangeKm: Double? { get }

    /// Profile's polling command retention policy: whether to retain unverified commands
    /// for raw capture and future decode discovery. Defaults to `false` (discard unverified).
    var retainUnverifiedPollingCommands: Bool { get }

    func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate?

    /// Like `parseResponse`, but allows emitting more than one `TelemetryUpdate` from a
    /// single OBD response — e.g. a payload that carries both SOC and SOH, or pack current
    /// and a 12V auxiliary voltage. Defaults to wrapping `parseResponse`'s single result, so
    /// conformers only need to override this when a response genuinely decodes to multiple
    /// metrics.
    func parseResponses(command: String, rawResponse: String) -> [TelemetryUpdate]
}

extension VehicleProfile {
    public var estimatedFullRangeKm: Double? { nil }

    public var retainUnverifiedPollingCommands: Bool { false }

    public func parseResponses(command: String, rawResponse: String) -> [TelemetryUpdate] {
        parseResponse(command: command, rawResponse: rawResponse).map { [$0] } ?? []
    }
}
