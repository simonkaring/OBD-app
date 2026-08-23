import SwiftUI

public struct OBDTerminalView: View {
    @ObservedObject public var vehicleData: VehicleDataManager
    @AppStorage("aiApiKey") private var aiApiKey: String = ""

    @State private var commandText = ""
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

    private var bluetoothManager: BluetoothManager? {
        vehicleData.obdConnection as? BluetoothManager
    }

    private var combinedLogs: [OBDLogEntry] {
        var logs = bluetoothManager?.log ?? []
        for manual in manualLogs {
            if !logs.contains(where: { $0.id == manual.id }) {
                logs.append(manual)
            }
        }
        return logs.sorted(by: { $0.timestamp < $1.timestamp })
    }

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
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
                        Label("AI Analyze", systemImage: "sparkles")
                            .foregroundColor(Theme.electricCyan)
                    }
                    .disabled(combinedLogs.isEmpty)

                    ShareLink(
                        item: AILogAnalyzer.buildAnalysisPrompt(log: combinedLogs, vehicleContext: vehicleData.vehicleName),
                        subject: Text("OBD CAN Trace - \(vehicleData.vehicleName)"),
                        message: Text("Help me decode this CAN trace for VoltLink")
                    ) {
                        Label("Export for AI", systemImage: "square.and.arrow.up")
                    }
                    .disabled(combinedLogs.isEmpty)
                }
                #else
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        showAISheet = true
                    } label: {
                        Label("AI Analyze", systemImage: "sparkles")
                    }
                    .disabled(combinedLogs.isEmpty)

                    ShareLink(
                        item: AILogAnalyzer.buildAnalysisPrompt(log: combinedLogs, vehicleContext: vehicleData.vehicleName),
                        subject: Text("OBD CAN Trace - \(vehicleData.vehicleName)"),
                        message: Text("Help me decode this CAN trace for VoltLink")
                    ) {
                        Label("Export for AI", systemImage: "square.and.arrow.up")
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
            }

            Section {
                HStack {
                    Text("Trace Log (\(combinedLogs.count) entries)")
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    if !combinedLogs.isEmpty {
                        Button("Clear") {
                            manualLogs.removeAll()
                        }
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    }
                }
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
        Task {
            let response = await sendCommandAsync(cmd)
            await MainActor.run {
                manualLogs.append(OBDLogEntry(timestamp: Date(), sent: cmd, response: response))
            }
        }
    }

    private func sendCommandAsync(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            vehicleData.obdConnection.sendCommand(command) { result in
                switch result {
                case .success(let raw): continuation.resume(returning: raw)
                case .failure(let err): continuation.resume(returning: "ERROR: \(err.localizedDescription)")
                }
            }
        }
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
                await MainActor.run {
                    manualLogs.append(OBDLogEntry(timestamp: Date(), sent: query, response: raw))
                }
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
                            manualLogs.append(OBDLogEntry(timestamp: Date(), sent: cmd, response: raw))
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
                            manualLogs.append(OBDLogEntry(timestamp: Date(), sent: "SP\(entry.protocol) \(header) 3E00", response: presentRaw))
                        }
                    }

                    let vinRaw = await sendCommandAsync("22F190")
                    if isProbeHit(vinRaw) {
                        await MainActor.run {
                            probeResults.append("SP\(entry.protocol) \(header) 22F190: \(vinRaw.trimmingCharacters(in: .whitespacesAndNewlines))")
                            manualLogs.append(OBDLogEntry(timestamp: Date(), sent: "SP\(entry.protocol) \(header) 22F190", response: vinRaw))
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
            .navigationTitle("AI CAN Analysis")
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
