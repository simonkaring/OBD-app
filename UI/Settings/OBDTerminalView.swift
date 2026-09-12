import SwiftUI
import UniformTypeIdentifiers

public struct OBDTerminalView: View {
    @ObservedObject public var vehicleData: VehicleDataManager

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
    }

    public var body: some View {
        if let bluetooth = vehicleData.obdConnection as? BluetoothManager {
            BluetoothTerminalView(vehicleData: vehicleData, bluetoothManager: bluetooth)
        } else {
            OBDTerminalContent(vehicleData: vehicleData, bluetoothManager: nil, bluetoothLogs: [])
        }
    }
}

private struct BluetoothTerminalView: View {
    let vehicleData: VehicleDataManager
    @ObservedObject var bluetoothManager: BluetoothManager

    var body: some View {
        OBDTerminalContent(vehicleData: vehicleData, bluetoothManager: bluetoothManager, bluetoothLogs: bluetoothManager.log)
    }
}

private struct OBDTerminalContent: View {
    @ObservedObject var vehicleData: VehicleDataManager
    let bluetoothManager: BluetoothManager?
    let bluetoothLogs: [OBDLogEntry]
    @AppStorage("aiApiKey") private var aiApiKey: String = ""

    @State private var commandText = ""
    @State private var commandError: String?
    @State private var supportedPIDs: [String] = []
    @State private var isScanningPIDs = false
    @State private var sweepResults: [String] = []
    @State private var isSweepingDIDs = false
    @State private var sweepProgress: Double = 0
    @State private var sweepTask: Task<Void, Never>?
    @State private var probeResults: [String] = []
    @State private var isProbing = false
    @State private var probeProgress: Double = 0

    @State private var manualLogs: [OBDLogEntry] = []
    @State private var showAISheet = false

    private var combinedLogs: [OBDLogEntry] {
        bluetoothManager == nil ? manualLogs : bluetoothLogs
    }

    public var body: some View {
        terminalList
            .navigationTitle("OBD Terminal")
            .inlineTitleDisplayMode()
            .toolbar {
                #if os(iOS)
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showAISheet = true
                    } label: {
                        Label("AI Analyze Recent (500 max)", systemImage: "sparkles")
                            .foregroundColor(Theme.electricCyan)
                    }
                    .disabled(combinedLogs.isEmpty)

                    ShareLink(
                        item: AILogAnalyzer.buildAnalysisPrompt(log: combinedLogs, vehicleContext: vehicleData.vehicleName),
                        subject: Text("OBD CAN Trace - \(vehicleData.vehicleName)"),
                        message: Text("Help me decode this CAN trace for VoltLink")
                    ) {
                        Label("Export Recent for AI (500 max)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(combinedLogs.isEmpty)
                }
                #else
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        showAISheet = true
                    } label: {
                        Label("AI Analyze Recent (500 max)", systemImage: "sparkles")
                    }
                    .disabled(combinedLogs.isEmpty)

                    ShareLink(
                        item: AILogAnalyzer.buildAnalysisPrompt(log: combinedLogs, vehicleContext: vehicleData.vehicleName),
                        subject: Text("OBD CAN Trace - \(vehicleData.vehicleName)"),
                        message: Text("Help me decode this CAN trace for VoltLink")
                    ) {
                        Label("Export Recent for AI (500 max)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(combinedLogs.isEmpty)
                }
                #endif
            }
            .sheet(isPresented: $showAISheet) {
                AIAnalysisSheet(
                    logs: combinedLogs,
                    vehicleContext: vehicleData.vehicleName,
                    apiKey: aiApiKey
                )
            }
    }

    @ViewBuilder
    private var terminalList: some View {
        List {
            if let bluetoothManager {
                BluetoothCaptureSection(bluetoothManager: bluetoothManager, vehicleContext: vehicleData.vehicleName)
            } else {
                Section("Diagnostic Capture") {
                    Text("File capture is available outside demo mode. Recent manual logs are shown below.")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }

            Section("Discovery Tools") {
                Button {
                    runSupportedPIDScan()
                } label: {
                    Label(isScanningPIDs ? "Scanning..." : "Scan Supported Mode 01 PIDs", systemImage: "magnifyingglass")
                }
                .disabled(isScanningPIDs || isSweepingDIDs || isProbing)

                if !supportedPIDs.isEmpty {
                    Text(supportedPIDs.joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Theme.electricCyan)
                }

                if isSweepingDIDs {
                    Button(role: .destructive) {
                        cancelSweep()
                    } label: {
                        Label("Cancel DID Sweep (\(Int(sweepProgress * 100))%)", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        runDIDSweep()
                    } label: {
                        Label("Sweep UDS DIDs (headers 7E0-7E7, 22 01 00-FF)", systemImage: "list.number")
                    }
                    .disabled(isScanningPIDs || isProbing)
                }

                ForEach(sweepResults, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Theme.regenGreen)
                }

                Button {
                    runBusProbe()
                } label: {
                    Label(isProbing ? "Probing... \(Int(probeProgress * 100))%" : "Bus Probe (find working protocol/header)", systemImage: "waveform.path.ecg")
                }
                .disabled(isProbing || isScanningPIDs || isSweepingDIDs)

                ForEach(probeResults, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Theme.regenGreen)
                }
            }

            Section("Send Raw Command") {
                HStack {
                    TextField("e.g. 220101 or AT SH 7E4", text: $commandText)
                        .autocorrectionDisabled()
                    Button("Send") {
                        sendManualCommand()
                    }
                    .disabled(commandText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let commandError {
                    Label(commandError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(Theme.criticalRed)
                }
            }

            Section {
                HStack {
                    Text("Recent Log (\(combinedLogs.count)/500)")
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    if !combinedLogs.isEmpty {
                        Button("Clear") {
                            bluetoothManager?.clearLog()
                            manualLogs.removeAll()
                        }
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    }
                }
                Text("AI analysis and AI export use only these recent entries, not the capture file. Clear does not erase the capture file.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            if combinedLogs.isEmpty {
                Text("No commands sent yet. Run a discovery tool or send a raw command above.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            } else {
                ForEach(combinedLogs.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("→ \(entry.sent)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Theme.electricCyan)
                        Text(entry.response.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\r", with: " "))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private func sendManualCommand() {
        let cmd = commandText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        commandText = ""
        commandError = nil
        Task {
            let response = await sendCommandAsync(cmd)
            commandError = response.hasPrefix("ERROR:") ? response : nil
        }
    }

    private func sendCommandAsync(_ command: String) async -> String {
        let connection = vehicleData.obdConnection
        let response: String = await withCheckedContinuation { continuation in
            connection.sendCommand(command) { result in
                switch result {
                case .success(let raw): continuation.resume(returning: raw)
                case .failure(let err): continuation.resume(returning: "ERROR: \(err.localizedDescription)")
                }
            }
        }
        // Bluetooth already logs at completion; only demo/non-Bluetooth needs a local tail.
        if !(connection is BluetoothManager) {
            await MainActor.run {
                manualLogs.append(OBDLogEntry(timestamp: Date(), sent: command, response: response))
                if manualLogs.count > BluetoothManager.maxLogEntries {
                    manualLogs.removeFirst(manualLogs.count - BluetoothManager.maxLogEntries)
                }
            }
        }
        return response
    }

    private func runSupportedPIDScan() {
        isScanningPIDs = true
        supportedPIDs = []
        vehicleData.stopPolling()
        Task {
            _ = await sendCommandAsync("AT SH 7DF")
            let queries = ["0100", "0120", "0140", "0160"]
            var found: [String] = []
            for query in queries {
                let raw = await sendCommandAsync(query)
                guard let pids = parsePIDBitmask(raw, query: query) else { break }
                found.append(contentsOf: pids)
            }
            await MainActor.run {
                supportedPIDs = found
                isScanningPIDs = false
                vehicleData.startPolling()
            }
        }
    }

    private func parsePIDBitmask(_ raw: String, query: String) -> [String]? {
        let clean = ISO15765Parser().assembleISOTPPayload(raw)
        let responseHeader = "41" + query.dropFirst(2)
        guard let range = clean.range(of: responseHeader) else { return nil }
        let after = String(clean[range.upperBound...])
        guard after.count >= 8, let mask = UInt32(after.prefix(8), radix: 16) else { return nil }
        guard let base = Int(query.dropFirst(2), radix: 16) else { return nil }

        var pids: [String] = []
        for bit in 0..<32 where mask & (1 << (31 - bit)) != 0 {
            pids.append(String(format: "01%02X", base + bit + 1))
        }
        return pids
    }

    private func runDIDSweep() {
        sweepResults = []
        sweepProgress = 0
        isSweepingDIDs = true
        vehicleData.stopPolling()
        sweepTask = Task {
            _ = await sendCommandAsync("AT SP 7")
            let headers = [
                ("18DA59F1", "BMS (0x59)"),
                ("18DA29F1", "Inverter (0x29)"),
                ("18DA17F1", "Charger (0x17)"),
                ("7E4", "BMS 11-bit"),
                ("7E0", "Powertrain 11-bit")
            ]
            let candidateLowBytes = Array(0x00...0x35) + [0x5B, 0x90, 0xA0, 0xAF]
            let total = headers.count * candidateLowBytes.count
            var done = 0
            for (header, label) in headers {
                if Task.isCancelled { break }
                _ = await sendCommandAsync("AT SH \(header)")
                _ = await sendCommandAsync("AT CRA")
                for low in candidateLowBytes {
                    if Task.isCancelled { break }
                    let didLow = String(format: "%02X", low)
                    let cmd = "2201\(didLow)"
                    let raw = await sendCommandAsync(cmd)
                    let clean = ISO15765Parser().assembleISOTPPayload(raw)
                    if isPositiveUDSResponse(clean) {
                        let line = "\(label) DID 01\(didLow): \(clean)"
                        await MainActor.run {
                            sweepResults.append(line)
                        }
                    }
                    done += 1
                    let progress = Double(done) / Double(total)
                    await MainActor.run { sweepProgress = progress }
                }
            }
            vehicleData.selectProfile(vehicleData.selectedProfileID)
            await MainActor.run {
                isSweepingDIDs = false
                vehicleData.startPolling()
            }
        }
    }

    private func isPositiveUDSResponse(_ hex: String) -> Bool {
        !hex.isEmpty && !hex.hasPrefix("7F") && hex.hasPrefix("62")
    }

    private func cancelSweep() {
        sweepTask?.cancel()
        isSweepingDIDs = false
        vehicleData.startPolling()
    }

    private static let probeMatrix: [(protocol: String, headers: [String])] = [
        ("6", ["7DF", "7E0", "7E4"]),
        ("7", ["18DB33F1", "18DA10F1", "18DA01F1"]),
        ("8", ["7DF", "7E0", "7E4"]),
        ("9", ["18DB33F1", "18DA10F1"]),
    ]

    private func isProbeHit(_ raw: String) -> Bool {
        let upper = raw.uppercased()
        let clean = upper.replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
        if clean.isEmpty || clean == "OK" { return false }
        let negativeMarkers = ["NO DATA", "ERROR", "UNABLE TO CONNECT", "BUS INIT", "CAN ERROR", "?", "STOPPED", "SEARCHING"]
        return !negativeMarkers.contains { clean.contains($0) }
    }

    private func runBusProbe() {
        probeResults = []
        probeProgress = 0
        isProbing = true
        vehicleData.stopPolling()
        Task {
            let matrix = Self.probeMatrix
            let totalHeaders = matrix.reduce(0) { $0 + $1.headers.count }
            var done = 0

            let voltage = await sendCommandAsync("AT RV")
            let ignition = await sendCommandAsync("AT IGN")
            await MainActor.run {
                probeResults.append("Port: \(voltage.trimmingCharacters(in: .whitespacesAndNewlines)) / IGN \(ignition.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            for entry in matrix {
                _ = await sendCommandAsync("AT SP \(entry.protocol)")
                for header in entry.headers {
                    _ = await sendCommandAsync("AT SH \(header)")
                    _ = await sendCommandAsync("AT CRA")

                    let presentRaw = await sendCommandAsync("3E00")
                    if isProbeHit(presentRaw) {
                        await MainActor.run {
                            probeResults.append("SP\(entry.protocol) \(header) 3E00: \(presentRaw.trimmingCharacters(in: .whitespacesAndNewlines))")
                        }
                    }

                    let vinRaw = await sendCommandAsync("22F190")
                    if isProbeHit(vinRaw) {
                        await MainActor.run {
                            probeResults.append("SP\(entry.protocol) \(header) 22F190: \(vinRaw.trimmingCharacters(in: .whitespacesAndNewlines))")
                        }
                    }

                    done += 1
                    let progress = Double(done) / Double(totalHeaders)
                    await MainActor.run { probeProgress = progress }
                }
                let status = await sendCommandAsync("AT CS")
                await MainActor.run {
                    probeResults.append("SP\(entry.protocol) CAN status: \(status.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }

            vehicleData.selectProfile(vehicleData.selectedProfileID)

            await MainActor.run {
                isProbing = false
                vehicleData.startPolling()
            }
        }
    }
}

private struct BluetoothCaptureSection: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    let vehicleContext: String
    @State private var confirmReplacement = false
    @State private var exportDocument: CaptureExportDocument?
    @State private var exportError: String?

    var body: some View {
        Section {
            Label(bluetoothManager.isCapturing ? "Capturing to File" : "Capture Stopped", systemImage: bluetoothManager.isCapturing ? "record.circle" : "stop.circle")

            if bluetoothManager.isCapturing {
                Button("Stop Capture") { bluetoothManager.stopCapture() }
            } else {
                Button("Start Capture") {
                    if bluetoothManager.captureFileURL != nil {
                        confirmReplacement = true
                    } else {
                        bluetoothManager.startCapture(vehicleContext: vehicleContext)
                    }
                }
            }

            if let url = bluetoothManager.captureFileURL {
                Button {
                    do {
                        exportDocument = CaptureExportDocument(data: try Data(contentsOf: url))
                    } catch {
                        exportError = "Could not read capture: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Export Capture File", systemImage: "square.and.arrow.up")
                }
                .disabled(bluetoothManager.isCapturing)
            }

            if let error = bluetoothManager.captureError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(Theme.criticalRed)
            }
        } header: {
            Text("Diagnostic Capture")
        } footer: {
            Text("Start before your drive. Only new completed Bluetooth commands are saved, including across reconnects. Stop to export. The file stays in Documents after relaunch; a new capture replaces it. Clear only clears recent logs.")
        }
        .confirmationDialog("Replace the Previous Capture?", isPresented: $confirmReplacement, titleVisibility: .visible) {
            Button("Replace and Start Capture", role: .destructive) {
                bluetoothManager.startCapture(vehicleContext: vehicleContext)
            }
        } message: {
            Text("Export the previous capture first if you want to keep it. Starting a new capture replaces that file.")
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: "VoltLink-OBD-Capture"
        ) { result in
            if case let .failure(error) = result {
                exportError = "Could not export capture: \(error.localizedDescription)"
            }
            exportDocument = nil
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }
}

private struct CaptureExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
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

public struct AIAnalysisSheet: View {
    public let logs: [OBDLogEntry]
    public let vehicleContext: String
    public let apiKey: String

    @State private var analysisResult: String?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Analyzing CAN bus responses with AI...")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error = errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Analysis Failed", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundColor(Theme.criticalRed)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)

                            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Tip: Go to Settings > Developer Tools and enter a Gemini or OpenAI API Key to enable in-app AI analysis.")
                                    .font(.caption)
                                    .foregroundColor(Theme.electricCyan)
                                    .padding(.top, 4)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                    } else if let result = analysisResult {
                        Text(result)
                            .font(.system(.body, design: .rounded))
                            .textSelection(.enabled)
                            .padding()
                            .glassCard()
                    }
                }
                .padding()
            }
            .navigationTitle("AI Recent Log Analysis")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                if let result = analysisResult {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = result
                            #endif
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            .task {
                await runAnalysis()
            }
        }
    }

    private func runAnalysis() async {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "No API Key configured. Please add an API Key under Settings > Developer Tools."
            return
        }

        isLoading = true
        errorMessage = nil
        analysisResult = nil

        do {
            let result = try await AILogAnalyzer.analyze(
                log: logs,
                vehicleContext: vehicleContext,
                apiKey: apiKey
            )
            analysisResult = result
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview("OBD Terminal") {
    NavigationStack {
        OBDTerminalView(vehicleData: VehicleDataManager())
    }
}
