import SwiftUI
import UniformTypeIdentifiers
import VoltLinkEngine

struct ProbeView: View {
    @StateObject private var probe = EQAProbeController()
    @State private var resultFilter = ProbeResult.Status.positive
    @State private var exporting = false

    var body: some View {
        TabView {
            LiveDataView(probe: probe)
                .tabItem { Label("Live Data", systemImage: "waveform.path.ecg") }

            discovery
                .tabItem { Label("Discovery", systemImage: "magnifyingglass") }
        }
        .padding()
    }

    private var discovery: some View {
        VStack(spacing: 14) {
            controls
            ProgressView(value: probe.progress) {
                Text(probe.isRunning ? probe.currentCommand : "Ready")
            }
            .opacity(probe.isRunning ? 1 : 0)

            HStack {
                Text("Results: \(probe.results.count)")
                Spacer()
                Picker("Show", selection: $resultFilter) {
                    Text("Positive").tag(ProbeResult.Status.positive)
                    Text("Negative").tag(ProbeResult.Status.negative)
                    Text("Errors").tag(ProbeResult.Status.adapterError)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            resultList
        }
        .fileExporter(
            isPresented: $exporting,
            document: ProbeExportDocument(data: probe.exportData ?? Data()),
            contentType: .json,
            defaultFilename: "eqa-probe-captures"
        ) { _ in }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text(connectionLabel)
                        .font(.headline)
                    Text("Read-only UDS discovery. Disconnect the iPhone before connecting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(probe.connectionState.isConnected ? "Disconnect" : "Connect iCar Pro") {
                    probe.connectionState.isConnected ? probe.disconnect() : probe.connect()
                }
            }

            HStack(spacing: 12) {
                Button("Full Discovery") { probe.startDiscovery() }
                    .disabled(!probe.connectionState.isConnected || probe.isRunning)
                Button("Repeat Positive DIDs") { probe.repeatPositiveDIDs() }
                    .disabled(!probe.connectionState.isConnected || probe.isRunning || !probe.captures.contains(where: { $0.kind == .discovery }))
                Button("Stop", role: .destructive) { probe.cancel() }
                    .disabled(!probe.isRunning)
                Button("Export JSON") { exporting = true }
                    .disabled(probe.captures.isEmpty)
            }
            CaptureReferenceFields(probe: probe)
        }
    }

    private var resultList: some View {
        List(probe.results.filter { $0.status == resultFilter }.reversed()) { result in
            HStack(alignment: .top, spacing: 12) {
                Text("0x\(result.ecu) / \(result.did)")
                    .frame(width: 120, alignment: .leading)
                Text(result.payload.isEmpty ? result.rawResponse.singleLine : result.payload)
                    .textSelection(.enabled)
                    .fontDesign(.monospaced)
                Spacer()
                Text("\(result.durationMs) ms")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .overlay {
            if probe.results.filter({ $0.status == resultFilter }).isEmpty {
                ContentUnavailableView("No \(resultFilter.rawValue) responses", systemImage: "waveform.path.ecg")
            }
        }
    }

    private var connectionLabel: String {
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

struct CaptureReferenceFields: View {
    @ObservedObject var probe: EQAProbeController

    var body: some View {
        GroupBox("Capture references (optional unless selected)") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Reference SOC")
                    Text("Ambient temp")
                    Text("Battery temp")
                    Text("Charger power")
                    Text("Measured 12V")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                GridRow {
                    TextField("%", value: $probe.referenceSOC, format: .number.precision(.fractionLength(1)))
                    TextField("°C", value: $probe.referenceAmbientTemperatureC, format: .number.precision(.fractionLength(1)))
                    TextField("°C", value: $probe.referenceBatteryTemperatureC, format: .number.precision(.fractionLength(1)))
                    TextField("kW", value: $probe.referenceChargerPowerKW, format: .number.precision(.fractionLength(1)))
                    TextField("V", value: $probe.referenceAuxVoltageV, format: .number.precision(.fractionLength(2)))
                }

                GridRow {
                    Picker("Plugged state", selection: $probe.referencePluggedState) {
                        ForEach(ProbePluggedState.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Charging type", selection: $probe.referenceChargingType) {
                        ForEach(ProbeChargingType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Vehicle state", selection: $probe.referenceVehicleState) {
                        ForEach(ProbeVehicleState.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .gridCellColumns(3)
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ProbeExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private extension String {
    var singleLine: String {
        replacing("\r", with: " ").replacing("\n", with: " ")
    }
}
