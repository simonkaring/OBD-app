import Foundation

/// Builds the portable OBD trace prompt used by the terminal's share sheet. VoltLink no longer
/// calls an AI provider itself; the trace can be pasted into any assistant the user prefers.
public struct OBDTraceExporter: Sendable {
    public static func buildAnalysisPrompt(log: [OBDLogEntry], vehicleContext: String = "") -> String {
        var text = """
            You are an expert automotive embedded systems engineer specializing in reverse engineering OBD-II (SAE J1979) and UDS (ISO 14229 / ISO 15765-4) CAN bus diagnostics for Electric Vehicles (EVs) and ICE cars.

            Vehicle Context: \(vehicleContext.isEmpty ? "Unknown / Not specified" : vehicleContext)

            Below is a trace of OBD commands sent to the vehicle and the raw hex responses received:

            ---
            """

        for entry in log {
            text += "\nTimestamp: \(entry.timestamp.ISO8601Format())\nSent: \(entry.sent)\nResponse:\n\(entry.response)\n"
        }

        text += """
            ---

            Please analyze the raw response data:
            1. Identify which ECUs/headers responded (e.g. BMS, Powertrain, Inverter, Charger, Gateway).
            2. Identify candidate PIDs/DIDs and positive responses (e.g. `62 xx xx` for UDS Service 0x22, `41 xx` for OBD-II Mode 01).
            3. For key EV metrics (State of Charge %, Pack Voltage, Pack Current / Power kW, Battery Temperatures, 12V Aux Voltage), identify candidate byte positions and formulas (e.g., bit scaling, offsets, signed vs unsigned integers).
            4. Provide ready-to-use Swift decoding snippet or a `VehicleProfile` implementation for VoltLink.
            """
        return text
    }
}
