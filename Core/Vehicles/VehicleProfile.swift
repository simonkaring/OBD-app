import Foundation

public protocol VehicleProfile: Sendable {
    var vehicleName: String { get }
    var isElectricVehicle: Bool { get }
    var batteryUsableCapacityKWh: Double { get }
    var initializationCommands: [String] { get }
    var pollingCommands: [String] { get }
    var supportedMetrics: Set<TelemetryMetric> { get }

    func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate?
}
