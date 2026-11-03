import XCTest

@testable import VoltLinkEngine

final class CommunityContributionTests: XCTestCase {
    private func log(_ command: String, _ response: String, at offset: TimeInterval = 0) -> OBDLogEntry {
        OBDLogEntry(timestamp: Date(timeIntervalSince1970: 1_700_000_000 + offset), sent: command, response: response)
    }

    func testDecodesEntriesThroughTheProfile() {
        let contribution = CommunityContributionBuilder.build(
            logs: [log("22010A", "62 01 0A 0F 8C\r\n>")],
            profile: MercedesEQA250Profile(),
            vehicleName: "EQA",
            profileID: "mercedesEQA250",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(contribution.schemaVersion, CommunityPIDContribution.currentSchemaVersion)
        XCTAssertEqual(contribution.entries.count, 1)
        let entry = contribution.entries[0]
        XCTAssertEqual(entry.command, "22010A")
        XCTAssertEqual(entry.observations, 1)
        XCTAssertEqual(entry.metrics.count, 1)
        XCTAssertEqual(entry.metrics[0].name, TelemetryMetric.packVoltage.displayName)
        XCTAssertEqual(entry.metrics[0].unit, "V")
        XCTAssertEqual(entry.metrics[0].value, 398, accuracy: 0.001, "0x0F8C * 0.1")
        XCTAssertFalse(entry.response.contains(">"), "The ELM prompt is stripped from the shared response")
    }

    func testCountsObservationsAndKeepsTheLatestDecode() {
        let contribution = CommunityContributionBuilder.build(
            logs: [
                log("22010A", "62 01 0A 0F 8C\r\n>", at: 0),
                log("22010a", "62 01 0A 0F 96\r\n>", at: 5),
            ],
            profile: MercedesEQA250Profile(),
            vehicleName: "EQA",
            profileID: "mercedesEQA250")

        XCTAssertEqual(contribution.entries.count, 1)
        XCTAssertEqual(contribution.entries[0].observations, 2)
        XCTAssertEqual(contribution.entries[0].metrics[0].value, 399, accuracy: 0.001)
    }

    func testSkipsFailuresAndCommandsTheProfileCannotDecode() {
        let contribution = CommunityContributionBuilder.build(
            logs: [
                log("22010A", "NO DATA"),
                log("22010A", "7F 22 31"),
                log("DEADBEEF", "62 DE AD BE EF"),
                log("22010A", "62 01 0A 0F 8C"),
            ],
            profile: MercedesEQA250Profile(),
            vehicleName: "EQA",
            profileID: "mercedesEQA250")

        XCTAssertEqual(contribution.entries.count, 1)
        XCTAssertEqual(contribution.entries[0].observations, 1)
    }

    func testMultiValuePayloadContributesEveryMetric() {
        let contribution = CommunityContributionBuilder.build(
            logs: [log("220101", "62 01 01 00 00")],
            profile: MultiValueProfile(),
            vehicleName: "Test EV",
            profileID: "test")

        XCTAssertEqual(contribution.entries.count, 1)
        XCTAssertEqual(
            Set(contribution.entries[0].metrics.map(\.name)),
            Set([TelemetryMetric.power.displayName, TelemetryMetric.packVoltage.displayName, TelemetryMetric.packCurrent.displayName]))
    }

    func testJSONRoundTripsAndFilenameIsSafe() throws {
        let contribution = CommunityContributionBuilder.build(
            logs: [log("22010A", "62 01 0A 0F 8C")],
            profile: MercedesEQA250Profile(),
            vehicleName: "Mercedes-Benz EQA 250 (2021)",
            profileID: "mercedesEQA250",
            appVersion: "2.3.4",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let json = try contribution.json()
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"))
        XCTAssertTrue(json.contains("2023-11-14T"), "Dates are ISO 8601")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CommunityPIDContribution.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, contribution)
        XCTAssertTrue(contribution.suggestedFilename.hasPrefix("VoltLink-PID-Contribution-"))
        XCTAssertTrue(contribution.suggestedFilename.hasSuffix(".json"))
        XCTAssertFalse(contribution.suggestedFilename.contains(" "))
    }

    func testEmptyLogProducesAnEmptyContribution() {
        let contribution = CommunityContributionBuilder.build(
            logs: [], profile: MercedesEQA250Profile(), vehicleName: "EQA", profileID: "mercedesEQA250")
        XCTAssertTrue(contribution.entries.isEmpty)
        XCTAssertEqual(contribution.metricCount, 0)
    }
}

/// Minimal profile used to prove a single payload can contribute several metrics.
private struct MultiValueProfile: VehicleProfile {
    let vehicleName = "Test EV"
    let isElectricVehicle = true
    let batteryUsableCapacityKWh: Double = 60
    let initializationCommands: [String] = []
    let pollingCommands: [String] = ["220101"]
    let supportedMetrics: Set<TelemetryMetric> = [.power, .packVoltage, .packCurrent]

    func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        .power(voltage: 400, current: -75, powerKW: 30)
    }
}
