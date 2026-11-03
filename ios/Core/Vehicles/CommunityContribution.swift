import Foundation

/// A shareable package of the commands VoltLink decoded for one vehicle.
///
/// The bundled profiles come from community catalogs (ABRP, OVMS, OBDb), but there was no
/// way to give discoveries back: the OBD terminal could export a raw trace or ask an AI, yet
/// nothing produced a structured contribution. This document lists each command that decoded
/// to a known metric, the response it decoded from, and the decoded values, so a maintainer
/// can review a decoding without replaying a whole capture.
public struct CommunityPIDContribution: Codable, Sendable, Equatable {
    public struct Metric: Codable, Sendable, Equatable {
        public let name: String
        public let unit: String
        public let value: Double

        public init(name: String, unit: String, value: Double) {
            self.name = name
            self.unit = unit
            self.value = value
        }
    }

    public struct Entry: Codable, Sendable, Equatable {
        public let command: String
        public let response: String
        /// How many times this command decoded successfully in the exported log.
        public let observations: Int
        public let metrics: [Metric]

        public init(command: String, response: String, observations: Int, metrics: [Metric]) {
            self.command = command
            self.response = response
            self.observations = observations
            self.metrics = metrics
        }
    }

    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let vehicleName: String
    public let profileID: String
    public let appVersion: String
    public let generatedAt: Date
    public let notes: String
    public let entries: [Entry]

    public init(
        vehicleName: String,
        profileID: String,
        appVersion: String,
        generatedAt: Date,
        notes: String = "",
        entries: [Entry]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.vehicleName = vehicleName
        self.profileID = profileID
        self.appVersion = appVersion
        self.generatedAt = generatedAt
        self.notes = notes
        self.entries = entries
    }

    public var metricCount: Int {
        entries.reduce(0) { $0 + $1.metrics.count }
    }

    public var suggestedFilename: String {
        let slug =
            vehicleName
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
        let collapsed = slug.split(separator: "-").joined(separator: "-")
        return "VoltLink-PID-Contribution-\(collapsed.isEmpty ? "vehicle" : collapsed).json"
    }

    /// Pretty-printed, key-sorted JSON with ISO 8601 timestamps.
    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

/// Builds a contribution from the OBD terminal's recent log and the active profile.
public enum CommunityContributionBuilder {
    /// Responses are trimmed to this many characters so a pathological multi-frame reply
    /// cannot produce an unusable document.
    public static let maximumResponseLength = 4_000

    public static func build(
        logs: [OBDLogEntry],
        profile: VehicleProfile,
        vehicleName: String,
        profileID: String,
        appVersion: String = "1.0",
        generatedAt: Date = .now
    ) -> CommunityPIDContribution {
        var entries: [String: CommunityPIDContribution.Entry] = [:]

        for log in logs {
            let command = log.sent.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !command.isEmpty, !isFailureResponse(log.response) else { continue }
            // Profiles match commands case-sensitively; fall back to the normalized spelling so
            // a hand-typed lowercase command still contributes.
            let decoded =
                decodedMetrics(profile: profile, command: log.sent, response: log.response)
                ?? decodedMetrics(profile: profile, command: command, response: log.response)
            guard let decoded, !decoded.isEmpty else { continue }

            let previous = entries[command]
            entries[command] = CommunityPIDContribution.Entry(
                command: command,
                response: cleanedResponse(log.response),
                observations: (previous?.observations ?? 0) + 1,
                metrics: decoded)
        }

        return CommunityPIDContribution(
            vehicleName: vehicleName,
            profileID: profileID,
            appVersion: appVersion,
            generatedAt: generatedAt,
            notes: "Exported from VoltLink's OBD terminal. Values are decoded by the active vehicle profile; raw responses are included for verification.",
            entries: entries.values.sorted { $0.command < $1.command }
        )
    }

    /// Runs one log entry through the profile and converts every emitted update into a metric.
    static func decodedMetrics(
        profile: VehicleProfile,
        command: String,
        response: String
    ) -> [CommunityPIDContribution.Metric]? {
        let updates = profile.parseResponses(command: command, rawResponse: response)
        guard !updates.isEmpty else { return nil }

        var metrics: [String: CommunityPIDContribution.Metric] = [:]
        for update in updates {
            for (metric, value) in update.contributedMetrics where value.isFinite {
                metrics[metric.displayName] = CommunityPIDContribution.Metric(
                    name: metric.displayName,
                    unit: metric.unitSymbol,
                    value: value)
            }
        }
        return metrics.isEmpty ? nil : metrics.values.sorted { $0.name < $1.name }
    }

    private static func isFailureResponse(_ raw: String) -> Bool {
        let upper = raw.uppercased()
        let trimmed = upper.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("7F") else { return true }
        return ["NO DATA", "ERROR", "UNABLE TO CONNECT", "CAN ERROR", "STOPPED", "BUS INIT", "?"]
            .contains { upper.contains($0) }
    }

    private static func cleanedResponse(_ raw: String) -> String {
        let cleaned = ISO15765Parser().cleanELMResponse(raw).replacingOccurrences(of: "\n", with: " ")
        return String(cleaned.prefix(maximumResponseLength))
    }
}

extension TelemetryUpdate {
    /// Metrics this update contributes to a community decoding document.
    ///
    /// Multi-value payloads (pack voltage + current + power, three battery temperatures)
    /// are all emitted: the point of a contribution is to show what one command revealed.
    /// Updates without a `TelemetryMetric` — raw text PIDs, HVAC power, and charge status
    /// without a rate — contribute nothing.
    var contributedMetrics: [(TelemetryMetric, Double)] {
        switch self {
        case .speed(let value):
            return [(.speed, value)]
        case .power(let voltage, let current, let powerKW):
            return [(.power, powerKW), (.packVoltage, voltage), (.packCurrent, current)]
        case .packVoltage(let value):
            return [(.packVoltage, value)]
        case .packCurrent(let value):
            return [(.packCurrent, value)]
        case .soc(let value):
            return [(.soc, value)]
        case .soh(let value):
            return [(.soh, value)]
        case .batteryTemp(let min, let max, let average):
            return [(.batteryTemp, average), (.batteryTempMin, min), (.batteryTempMax, max)]
        case .aux12V(let value):
            return [(.aux12V, value)]
        case .motorStats(let rpm, let torque):
            return [(.motorRpm, rpm), (.motorTorque, torque)]
        case .motorRpm(let value):
            return [(.motorRpm, value)]
        case .motorTorque(let value):
            return [(.motorTorque, value)]
        case .fuelLevel(let value):
            return [(.fuelLevel, value)]
        case .throttlePosition(let value):
            return [(.throttlePosition, value)]
        case .engineLoad(let value):
            return [(.engineLoad, value)]
        case .coolantTemp(let value):
            return [(.coolantTemp, value)]
        case .intakeAirTemp(let value):
            return [(.intakeAirTemp, value)]
        case .ambientAirTemp(let value):
            return [(.ambientAirTemp, value)]
        case .maf(let value):
            return [(.maf, value)]
        case .manifoldPressure(let value):
            return [(.manifoldPressure, value)]
        case .oilTemp(let value):
            return [(.oilTemp, value)]
        case .timingAdvance(let value):
            return [(.timingAdvance, value)]
        case .barometricPressure(let value):
            return [(.barometricPressure, value)]
        case .vehicleRange(let value):
            return [(.vehicleRange, value)]
        case .communityMetric(let metric, let value):
            return [(metric, value)]
        case .hvacPower, .chargingStats, .genericPid:
            return []
        }
    }
}
