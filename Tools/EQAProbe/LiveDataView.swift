import SwiftUI
import VoltLinkEngine

struct LiveDataView: View {
    @ObservedObject var probe: EQAProbeController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(connectionTitle).font(.headline)
                    Text("Read-only BMS polling. Values without a verified decoder stay unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(probe.connectionState.isConnected ? "Disconnect" : "Connect iCar Pro") {
                    probe.connectionState.isConnected ? probe.disconnect() : probe.connect()
                }
                Button(probe.isLivePolling ? "Stop Live Data" : "Start Live Data") {
                    probe.isLivePolling ? probe.cancel() : probe.startLiveData()
                }
                .disabled(!probe.connectionState.isConnected || (!probe.isLivePolling && probe.isRunning))
            }

            HStack(alignment: .top, spacing: 24) {
                GroupBox("Telemetry") {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                        row("State of charge", percent(probe.telemetry.stateOfChargePct, updated: probe.telemetry.socUpdatedAt))
                        row("Remaining energy candidate (unverified)", energy(probe.remainingEnergyKWh))
                        row("Pack voltage", voltage(probe.telemetry.voltageV))
                        row("Pack current", current(probe.telemetry.currentA))
                        row("Calculated pack power", power(probe.telemetry.powerKW))
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Charging") {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                        row("Plugged state", probe.referencePluggedState.rawValue)
                        row("Charging type", probe.referenceChargingType.rawValue)
                        row("Reference charger power", referenceChargerPower)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Current session") {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                        row("Elapsed", elapsed)
                        row("SOC change", socChange)
                        row("Raw samples", probe.liveResponses.count.formatted())
                        row("Vehicle state", probe.referenceVehicleState.rawValue)
                    }
                    .padding(.vertical, 4)
                }
            }

            CaptureReferenceFields(probe: probe)

            GroupBox("Timestamped raw samples") {
                List(probe.liveResponses.reversed()) { result in
                    HStack(alignment: .firstTextBaseline) {
                        Text(result.capturedAt, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                            .monospacedDigit()
                            .frame(width: 105, alignment: .leading)
                        Text("0x\(result.ecu) / \(result.did)").frame(width: 120, alignment: .leading)
                        Text(result.payload.isEmpty ? result.rawResponse.replacing("\r", with: " ").replacing("\n", with: " ") : result.payload)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
                        Spacer()
                        Text(result.status.rawValue).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                .frame(minHeight: 180)
                .overlay {
                    if probe.liveResponses.isEmpty {
                        ContentUnavailableView("No live responses", systemImage: "bolt.slash", description: Text("Connect, then start live data."))
                    }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func percent(_ value: Double, updated: Date?) -> String {
        guard updated != nil else { return "Unavailable" }
        return "\(value.formatted(.number.precision(.fractionLength(3))))%"
    }

    private func voltage(_ value: Double) -> String {
        value > 0 ? "\(value.formatted(.number.precision(.fractionLength(1)))) V" : "Unavailable"
    }

    private func energy(_ value: Double?) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(3)))) kWh" } ?? "Unavailable"
    }

    private func current(_ value: Double) -> String {
        guard probe.liveResponses.contains(where: { $0.did == "010B" && $0.status == .positive }) else { return "Unavailable" }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) A"
    }

    private func power(_ value: Double) -> String {
        guard probe.telemetry.voltageV > 0,
              probe.liveResponses.contains(where: { $0.did == "010B" && $0.status == .positive }) else { return "Unavailable" }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) kW"
    }

    private var referenceChargerPower: String {
        guard let value = probe.referenceChargerPowerKW else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) kW"
    }

    private var socChange: String {
        guard let start = probe.sessionStartSOC else { return "—" }
        let change = probe.telemetry.stateOfChargePct - start
        return "\(change.formatted(.number.precision(.fractionLength(3))))%"
    }

    private var elapsed: String {
        guard let started = probe.sessionStartedAt else { return "—" }
        return (Date.now.timeIntervalSince(started)).formatted(.number.precision(.fractionLength(0))) + " sec"
    }

    private var connectionTitle: String {
        switch probe.connectionState {
        case .ready(let device): return "Connected: \(device)"
        case .connecting(let device): return "Connecting: \(device)"
        case .scanning: return "Scanning for adapter…"
        case .error(let message): return "Connection error: \(message)"
        case .demoMode: return "Demo mode"
        case .disconnected: return "Adapter disconnected"
        }
    }
}
