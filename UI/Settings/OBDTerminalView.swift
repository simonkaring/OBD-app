import SwiftUI

public struct OBDTerminalView: View {
    @ObservedObject public var vehicleData: VehicleDataManager

    @State private var commandText = ""
    @State private var supportedPIDs: [String] = []
    @State private var isScanningPIDs = false
    @State private var sweepResults: [String] = []
    @State private var isSweepingDIDs = false
    @State private var sweepProgress: Double = 0
    @State private var sweepTask: Task<Void, Never>?

    private var bluetoothManager: BluetoothManager? {
        vehicleData.obdConnection as? BluetoothManager
    }

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
    }

    public var body: some View {
        Group {
            if let manager = bluetoothManager {
                terminalList(manager: manager)
            } else {
                ContentUnavailableCompat(message: "The OBD terminal talks directly to the BLE adapter. Turn off Demo Mode and connect to a real adapter to use it.")
            }
        }
        .navigationTitle("OBD Terminal")
        .inlineTitleDisplayMode()
    }

    @ViewBuilder
    private func terminalList(manager: BluetoothManager) -> some View {
        List {
            Section("Discovery Tools") {
                Button {
                    runSupportedPIDScan()
                } label: {
                    Label(isScanningPIDs ? "Scanning..." : "Scan Supported Mode 01 PIDs", systemImage: "magnifyingglass")
                }
                .disabled(isScanningPIDs || isSweepingDIDs)

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
                    .disabled(isScanningPIDs)
                }

                ForEach(sweepResults, id: \.self) { line in
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
                        let cmd = commandText.trimmingCharacters(in: .whitespaces)
                        commandText = ""
                        vehicleData.obdConnection.sendCommand(cmd, completion: nil)
                    }
                    .disabled(commandText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                HStack {
                    Text("Log (\(manager.log.count) entries)")
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    if !manager.log.isEmpty {
                        ShareLink(item: exportText(manager.log)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }

            ForEach(manager.log.reversed()) { entry in
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
        Task {
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
        sweepTask = Task {
            let headers = ["7E0", "7E1", "7E2", "7E3", "7E4", "7E5", "7E6", "7E7"]
            let total = headers.count * 256
            var done = 0
            for header in headers {
                if Task.isCancelled { break }
                _ = await sendCommandAsync("AT SH \(header)")
                for low in 0...255 {
                    if Task.isCancelled { break }
                    let didLow = String(format: "%02X", low)
                    let raw = await sendCommandAsync("2201\(didLow)")
                    let clean = ISO15765Parser().assembleISOTPPayload(raw)
                    if isPositiveUDSResponse(clean) {
                        let line = "\(header) DID 01\(didLow): \(clean)"
                        await MainActor.run { sweepResults.append(line) }
                    }
                    done += 1
                    let progress = Double(done) / Double(total)
                    await MainActor.run { sweepProgress = progress }
                }
            }
            await MainActor.run { isSweepingDIDs = false }
        }
    }

    private func isPositiveUDSResponse(_ hex: String) -> Bool {
        !hex.isEmpty && !hex.hasPrefix("7F") && hex.hasPrefix("62")
    }

    private func cancelSweep() {
        sweepTask?.cancel()
        isSweepingDIDs = false
    }

    private func exportText(_ log: [OBDLogEntry]) -> String {
        log.map { entry in
            "\(entry.timestamp.formatted(date: .omitted, time: .standard)) → \(entry.sent)\n\(entry.response)"
        }.joined(separator: "\n---\n")
    }
}

private struct ContentUnavailableCompat: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundColor(Theme.textSecondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview("OBD Terminal") {
    NavigationStack {
        OBDTerminalView(vehicleData: VehicleDataManager())
    }
}
