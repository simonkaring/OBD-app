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
    let capturedAt: Date
    let ecu: String
    let did: String
    let rawResponse: String
    let payload: String
    let status: Status
    let durationMs: Int
}

enum ProbeCaptureKind: String, Codable {
    case discovery
    case liveData
}

enum ProbePluggedState: String, Codable, CaseIterable, Identifiable {
    case unknown = "Unknown"
    case unplugged = "Unplugged"
    case plugged = "Plugged in"

    var id: Self { self }
}

enum ProbeChargingType: String, Codable, CaseIterable, Identifiable {
    case unknown = "Unknown"
    case ac = "AC"
    case dc = "DC"

    var id: Self { self }
}

enum ProbeVehicleState: String, Codable, CaseIterable, Identifiable {
    case unknown = "Unknown"
    case parked = "Parked"
    case ready = "Ready"
    case driving = "Driving"
    case charging = "Charging"

    var id: Self { self }
}

struct ProbeReferences: Codable {
    let socPercent: Double?
    let ambientTemperatureC: Double?
    let batteryTemperatureC: Double?
    let pluggedState: ProbePluggedState
    let chargingType: ProbeChargingType
    let chargerPowerKW: Double?
    let vehicleState: ProbeVehicleState
    let auxiliaryVoltageV: Double?
}

struct ProbeCapture: Codable, Identifiable {
    let id: UUID
    let kind: ProbeCaptureKind
    let startedAt: Date
    let finishedAt: Date
    let references: ProbeReferences
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
    @Published private(set) var remainingEnergyKWh: Double?
    @Published private(set) var liveResponses: [ProbeResult] = []
    @Published private(set) var isLivePolling = false
    @Published private(set) var sessionStartedAt: Date?
    @Published private(set) var sessionStartSOC: Double?
    @Published var referenceSOC: Double?
    @Published var referenceAmbientTemperatureC: Double?
    @Published var referenceBatteryTemperatureC: Double?
    @Published var referencePluggedState = ProbePluggedState.unknown
    @Published var referenceChargingType = ProbeChargingType.unknown
    @Published var referenceChargerPowerKW: Double?
    @Published var referenceVehicleState = ProbeVehicleState.unknown
    @Published var referenceAuxVoltageV: Double?

    private let connection = BluetoothManager()
    private let parser = ISO15765Parser()
    private let profile = MercedesEQA250Profile()
    private var scanTask: Task<Void, Never>?

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
        remainingEnergyKWh = nil
        liveResponses = []
        sessionStartedAt = .now
        sessionStartSOC = nil
        let references = currentReferences
        scanTask = Task { [weak self] in
            await self?.runLiveData(references: references)
        }
    }

    func repeatPositiveDIDs() {
        guard let previous = captures.last(where: { $0.kind == .discovery }) else { return }
        let didsByECU = Dictionary(grouping: previous.results.filter { $0.status == .positive }, by: \.ecu)
            .mapValues { Set($0.compactMap { Int($0.did, radix: 16) }).sorted() }
        guard !didsByECU.isEmpty else { return }
        start(didsByECU: didsByECU)
    }

    func cancel() {
        scanTask?.cancel()
        currentCommand = "Stopping…"
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
        guard referenceSOC.map({ (0...100).contains($0) }) ?? true,
              referenceChargerPowerKW.map({ $0 >= 0 }) ?? true else { return }

        results = []
        progress = 0
        isRunning = true
        let references = currentReferences
        scanTask = Task { [weak self] in
            await self?.runScan(didsByECU: didsByECU, references: references)
        }
    }

    private func runScan(didsByECU: [String: [Int]], references: ProbeReferences) async {
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
                let capturedAt = Date.now
                let began = ContinuousClock.now
                let raw = await send("22\(didText)")
                let elapsed = began.duration(to: .now)
                results.append(makeResult(ecu: ecu, did: didText, raw: raw, capturedAt: capturedAt, duration: elapsed))
                completed += 1
                progress = total == 0 ? 1 : Double(completed) / Double(total)
            }
        }

        if !Task.isCancelled {
            captures.append(ProbeCapture(
                id: UUID(),
                kind: .discovery,
                startedAt: startedAt,
                finishedAt: .now,
                references: references,
                adapterInfo: adapterInfo,
                results: results
            ))
        }
        finish()
    }

    private func runLiveData(references: ProbeReferences) async {
        let startedAt = sessionStartedAt ?? .now
        var adapterInfo: [String: String] = [:]
        for command in profile.initializationCommands {
            guard !Task.isCancelled else {
                finishLiveData(startedAt: startedAt, references: references, adapterInfo: adapterInfo)
                return
            }
            currentCommand = command
            _ = await send(command)
        }

        for command in ["ATI", "AT@1", "AT DP", "AT RV"] {
            guard !Task.isCancelled else {
                finishLiveData(startedAt: startedAt, references: references, adapterInfo: adapterInfo)
                return
            }
            adapterInfo[command] = await send(command).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        while !Task.isCancelled {
            for command in ["22010A", "22010B", "22010C", "220210"] {
                guard !Task.isCancelled else {
                    finishLiveData(startedAt: startedAt, references: references, adapterInfo: adapterInfo)
                    return
                }
                currentCommand = command
                let capturedAt = Date.now
                let began = ContinuousClock.now
                let raw = await send(command)
                let elapsed = began.duration(to: .now)
                let result = makeResult(ecu: "59", did: String(command.dropFirst(2)), raw: raw, capturedAt: capturedAt, duration: elapsed)
                liveResponses.append(result)
                if command == "220210" {
                    remainingEnergyKWh = rawRemainingEnergy(from: raw)
                }
                if let update = profile.parseResponse(command: command, rawResponse: raw) {
                    applyLiveUpdate(update)
                }
            }
        }
        finishLiveData(startedAt: startedAt, references: references, adapterInfo: adapterInfo)
    }

    private func applyLiveUpdate(_ update: TelemetryUpdate) {
        var snapshot = telemetry
        snapshot.timestamp = .now
        switch update {
        case .packVoltage(let voltage):
            snapshot.voltageV = voltage
            updatePackPower(snapshot: &snapshot)
        case .packCurrent(let current):
            snapshot.currentA = current
            updatePackPower(snapshot: &snapshot)
        case .soc(let soc):
            snapshot.stateOfChargePct = soc
            snapshot.socUpdatedAt = snapshot.timestamp
            sessionStartSOC = sessionStartSOC ?? soc
        default:
            break
        }
        telemetry = snapshot
    }

    private func rawRemainingEnergy(from rawResponse: String) -> Double? {
        let payload = parser.assembleISOTPPayload(rawResponse)
        guard let marker = payload.range(of: "620210") else { return nil }
        let suffix = payload[marker.upperBound...]
        guard suffix.count >= 10 else { return nil }

        var bytes: [UInt8] = []
        var index = suffix.startIndex
        for _ in 0..<5 {
            let next = suffix.index(index, offsetBy: 2)
            guard let byte = UInt8(suffix[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        guard bytes[0] == 0x04 else { return nil }
        let high = UInt32(bytes[1]) << 24 | UInt32(bytes[2]) << 16
        let low = UInt32(bytes[3]) << 8 | UInt32(bytes[4])
        let raw = high | low
        let value = Double(raw) / 250.0
        return (0...70).contains(value) ? value : nil
    }

    private func updatePackPower(snapshot: inout TelemetrySnapshot) {
        guard snapshot.voltageV > 0 else { return }
        snapshot.powerKW = snapshot.voltageV * snapshot.currentA / 1_000
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

    private func makeResult(ecu: String, did: String, raw: String, capturedAt: Date, duration: Duration) -> ProbeResult {
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
        return ProbeResult(id: UUID(), capturedAt: capturedAt, ecu: ecu, did: did, rawResponse: raw, payload: payload, status: status, durationMs: milliseconds)
    }

    private func finish() {
        isRunning = false
        scanTask = nil
        currentCommand = ""
        progress = Task.isCancelled ? progress : 1
    }

    private func finishLiveData(startedAt: Date, references: ProbeReferences, adapterInfo: [String: String]) {
        if !liveResponses.isEmpty {
            captures.append(ProbeCapture(
                id: UUID(),
                kind: .liveData,
                startedAt: startedAt,
                finishedAt: .now,
                references: references,
                adapterInfo: adapterInfo,
                results: liveResponses
            ))
        }
        isRunning = false
        isLivePolling = false
        scanTask = nil
        currentCommand = ""
    }

    private var currentReferences: ProbeReferences {
        ProbeReferences(
            socPercent: referenceSOC,
            ambientTemperatureC: referenceAmbientTemperatureC,
            batteryTemperatureC: referenceBatteryTemperatureC,
            pluggedState: referencePluggedState,
            chargingType: referenceChargingType,
            chargerPowerKW: referenceChargerPowerKW,
            vehicleState: referenceVehicleState,
            auxiliaryVoltageV: referenceAuxVoltageV
        )
    }
}

private extension JSONEncoder {
    static var probe: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
