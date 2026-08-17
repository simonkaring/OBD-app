import Combine
import Foundation
import VoltLinkEngine

struct ProbeResult: Codable, Identifiable {
    enum Status: String, Codable {
        case positive
        case negative
        case adapterError
        case timeout
    }

    let id: UUID
    let ecu: String
    let did: String
    let rawResponse: String
    let payload: String
    let status: Status
    let durationMs: Int
}

struct ProbeCapture: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    let referenceSOC: Double
    let referencePowerKW: Double
    let adapterInfo: [String: String]
    let results: [ProbeResult]
}

@MainActor
final class EQAProbeController: NSObject, ObservableObject, OBDConnectionDelegate {
    @Published private(set) var connectionState: BLEConnectionState = .disconnected
    @Published private(set) var isRunning = false
    @Published private(set) var progress = 0.0
    @Published private(set) var currentCommand = ""
    @Published private(set) var results: [ProbeResult] = []
    @Published private(set) var captures: [ProbeCapture] = []
    @Published private(set) var telemetry = TelemetrySnapshot()
    @Published private(set) var liveResponses: [ProbeResult] = []
    @Published private(set) var isLivePolling = false
    @Published private(set) var sessionStartedAt: Date?
    @Published private(set) var sessionStartSOC: Double?
    @Published var referenceSOC = 0.0
    @Published var referencePowerKW = 0.0

    private let connection = BluetoothManager()
    private let parser = ISO15765Parser()
    private let profile = MercedesEQA250Profile()
    private var scanTask: Task<Void, Never>?
    private var liveSOCHistory: [(timestamp: Date, value: Double)] = []

    private static let ecus = ["17", "29", "59"]
    private static let discoveryDIDs = (Array(0x0000...0x02FF) + Array(0xF100...0xF1FF)).filter { $0 != 0xF190 }

    override init() {
        super.init()
        connection.delegate = self
        connectionState = connection.state
    }

    func connect() {
        connection.connect(peripheralName: nil)
    }

    func disconnect() {
        cancel()
        connection.disconnect()
    }

    func startDiscovery() {
        start(didsByECU: Dictionary(uniqueKeysWithValues: Self.ecus.map { ($0, Self.discoveryDIDs) }))
    }

    func startLiveData() {
        guard connectionState.isConnected, !isRunning else { return }
        isRunning = true
        isLivePolling = true
        telemetry = TelemetrySnapshot()
        liveResponses = []
        liveSOCHistory = []
        sessionStartedAt = .now
        sessionStartSOC = nil
        scanTask = Task { [weak self] in
            await self?.runLiveData()
        }
    }

    func repeatPositiveDIDs() {
        guard let previous = captures.last else { return }
        let didsByECU = Dictionary(grouping: previous.results.filter { $0.status == .positive }, by: \.ecu)
            .mapValues { Set($0.compactMap { Int($0.did, radix: 16) }).sorted() }
        guard !didsByECU.isEmpty else { return }
        start(didsByECU: didsByECU)
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isRunning = false
        isLivePolling = false
        currentCommand = ""
    }

    var exportData: Data? {
        try? JSONEncoder.probe.encode(captures)
    }

    nonisolated func obdConnectionDidReceiveResponse(command: String, rawResponse: String) {}

    nonisolated func obdConnectionStateDidChange(_ state: BLEConnectionState) {
        Task { @MainActor [weak self] in
            self?.connectionState = state
        }
    }

    private func start(didsByECU: [String: [Int]]) {
        guard connectionState.isConnected, !isRunning else { return }
        guard (0...100).contains(referenceSOC), referencePowerKW >= 0 else { return }

        results = []
        progress = 0
        isRunning = true
        scanTask = Task { [weak self] in
            await self?.runScan(didsByECU: didsByECU)
        }
    }

    private func runScan(didsByECU: [String: [Int]]) async {
        let startedAt = Date.now
        var adapterInfo: [String: String] = [:]
        for command in ["AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT CAF 1", "AT SP 7", "AT CP 18", "AT ST FF", "AT AL"] {
            guard !Task.isCancelled else { finish() ; return }
            _ = await send(command)
        }
        for command in ["ATI", "AT@1", "AT DP", "AT RV"] {
            guard !Task.isCancelled else { finish() ; return }
            adapterInfo[command] = await send(command).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let total = didsByECU.values.reduce(0) { $0 + $1.count }
        var completed = 0
        for ecu in Self.ecus {
            guard let dids = didsByECU[ecu], !Task.isCancelled else { break }
            guard await configure(ecu: ecu), !Task.isCancelled else {
                completed += dids.count
                progress = total == 0 ? 1 : Double(completed) / Double(total)
                continue
            }

            let liveness = await send("3E00")
            guard isLive(liveness) else {
                completed += dids.count
                progress = total == 0 ? 1 : Double(completed) / Double(total)
                continue
            }

            for did in dids {
                guard !Task.isCancelled else { break }
                let didText = String(format: "%04X", did)
                currentCommand = "ECU 0x\(ecu) · 22\(didText)"
                let began = ContinuousClock.now
                let raw = await send("22\(didText)")
                let elapsed = began.duration(to: .now)
                results.append(makeResult(ecu: ecu, did: didText, raw: raw, duration: elapsed))
                completed += 1
                progress = total == 0 ? 1 : Double(completed) / Double(total)
            }
        }

        if !Task.isCancelled {
            captures.append(ProbeCapture(
                id: UUID(),
                startedAt: startedAt,
                referenceSOC: referenceSOC,
                referencePowerKW: referencePowerKW,
                adapterInfo: adapterInfo,
                results: results
            ))
        }
        finish()
    }

    private func runLiveData() async {
        for command in profile.initializationCommands {
            guard !Task.isCancelled else { finishLiveData(); return }
            currentCommand = command
            _ = await send(command)
        }

        while !Task.isCancelled {
            for command in ["22010A", "220210"] {
                guard !Task.isCancelled else { finishLiveData(); return }
                currentCommand = command
                let began = ContinuousClock.now
                let raw = await send(command)
                let elapsed = began.duration(to: .now)
                let result = makeResult(ecu: "59", did: String(command.dropFirst(2)), raw: raw, duration: elapsed)
                liveResponses.removeAll { $0.did == result.did }
                liveResponses.append(result)
                if let update = profile.parseResponse(command: command, rawResponse: raw) {
                    applyLiveUpdate(update)
                }
            }
        }
        finishLiveData()
    }

    private func applyLiveUpdate(_ update: TelemetryUpdate) {
        var snapshot = telemetry
        snapshot.timestamp = .now
        switch update {
        case .packVoltage(let voltage):
            snapshot.voltageV = voltage
        case .soc(let soc):
            snapshot.stateOfChargePct = soc
            snapshot.socUpdatedAt = snapshot.timestamp
            sessionStartSOC = sessionStartSOC ?? soc
            updateLiveChargingPower(soc: soc, snapshot: &snapshot)
        default:
            break
        }
        telemetry = snapshot
    }

    private func updateLiveChargingPower(soc: Double, snapshot: inout TelemetrySnapshot) {
        liveSOCHistory.append((snapshot.timestamp, soc))
        liveSOCHistory.removeAll { $0.timestamp < snapshot.timestamp.addingTimeInterval(-90) }
        guard let oldest = liveSOCHistory.first else { return }
        let duration = snapshot.timestamp.timeIntervalSince(oldest.timestamp)
        let delta = soc - oldest.value
        guard duration >= 30, delta >= 0.04 else { return }
        let kw = (delta / 100 * profile.batteryUsableCapacityKWh) / (duration / 3_600)
        guard (0.5...200).contains(kw) else { return }
        snapshot.isCharging = true
        snapshot.chargePowerKW = kw
        snapshot.powerKW = -kw
        snapshot.chargePowerUpdatedAt = snapshot.timestamp
    }

    private func configure(ecu: String) async -> Bool {
        for command in [
            "AT SH 18DA\(ecu)F1",
            "AT CRA 18DAF1\(ecu)",
            "AT FCSH 18DA\(ecu)F1",
            "AT FCSD 300000",
            "AT FCSM 1"
        ] {
            let raw = await send(command)
            if raw.uppercased().contains("ERROR") { return false }
        }
        return true
    }

    private func send(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            connection.sendCommand(command) { result in
                switch result {
                case .success(let raw): continuation.resume(returning: raw)
                case .failure(let error): continuation.resume(returning: "ERROR: \(error.localizedDescription)")
                }
            }
        }
    }

    private func isLive(_ raw: String) -> Bool {
        let upper = raw.uppercased()
        return !["NO DATA", "ERROR", "TIMEOUT", "CAN ERROR", "UNABLE TO CONNECT"].contains { upper.contains($0) }
    }

    private func makeResult(ecu: String, did: String, raw: String, duration: Duration) -> ProbeResult {
        let payload = parser.assembleISOTPPayload(raw)
        let upper = raw.uppercased()
        let status: ProbeResult.Status
        if payload.hasPrefix("62") {
            status = .positive
        } else if payload.hasPrefix("7F") {
            status = .negative
        } else if upper.contains("TIMEOUT") {
            status = .timeout
        } else {
            status = .adapterError
        }
        let milliseconds = Int(Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
        return ProbeResult(id: UUID(), ecu: ecu, did: did, rawResponse: raw, payload: payload, status: status, durationMs: milliseconds)
    }

    private func finish() {
        isRunning = false
        scanTask = nil
        currentCommand = ""
        progress = Task.isCancelled ? progress : 1
    }

    private func finishLiveData() {
        isRunning = false
        isLivePolling = false
        scanTask = nil
        currentCommand = ""
    }
}

private extension JSONEncoder {
    static var probe: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
