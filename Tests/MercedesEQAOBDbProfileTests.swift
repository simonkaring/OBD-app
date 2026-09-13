import XCTest
@testable import VoltLinkEngine

final class MercedesEQAOBDbProfileTests: XCTestCase {
    private let profile = MercedesEQAOBDbProfile()

    func testPublishedFormulasAndMalformedResponses() {
        // Synthetic vectors exercise published math, not real-car compatibility.
        guard case .soc(let soc) = profile.parseResponse(command: "22 60 50", rawResponse: "7ED 05 62 60 50 1F A4") else { return XCTFail("SOC") }
        XCTAssertEqual(soc, 81)
        guard case .packVoltage(let voltage) = profile.parseResponse(command: "226075", rawResponse: "7ED 05 62 60 75 3E 80") else { return XCTFail("Voltage") }
        XCTAssertEqual(voltage, 400)
        guard case .packCurrent(let current) = profile.parseResponse(command: "226053", rawResponse: "7ED 05 62 60 53 FC 18") else { return XCTFail("Current") }
        XCTAssertEqual(current, -100)
        guard case .coolantTemp(let temperature) = profile.parseResponse(command: "222526", rawResponse: "7ED 05 62 25 26 FF B0") else { return XCTFail("Coolant") }
        XCTAssertEqual(temperature, -10)
        guard case .aux12V(let aux) = profile.parseResponse(command: "222005", rawResponse: "7ED 04 62 20 05 80") else { return XCTFail("12 V") }
        XCTAssertEqual(aux, 128 * 25.9 / 255, accuracy: 0.001)
        let wheels = "7EA 10 0B 62 20 01 04 00 04\r7EA 21 00 04 00 04 00 00 00"
        guard case .speed(let speed) = profile.parseResponse(command: "222001", rawResponse: wheels) else { return XCTFail("Multi-frame wheel speed") }
        XCTAssertEqual(speed, 57.6, accuracy: 0.001)
        XCTAssertFalse(profile.supportedMetrics.contains(.batteryTemp))
        for response in ["NO DATA", "7ED 03 7F 22 31", "7ED 04 62 60 50 1F", "7ED 05 62 60 50 FF FF", "7ED 05 62 60 53 1F A4", "7EC 05 62 60 50 1F A4", "62 60 50 1F A4"] {
            XCTAssertNil(profile.parseResponse(command: "226050", rawResponse: response), response)
        }
    }

    @MainActor
    func testSelectableProfileRestoresAndFeedsChargingWithoutInventingCellTemperature() throws {
        let suite = "EQAOBDbTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vehicle = try XCTUnwrap(VehicleCatalog.allModels.first { $0.id == "mb-eqa-250-obdb" })
        XCTAssertEqual(vehicle.telemetrySupport, .community)
        let manager = VehicleDataManager(userDefaults: defaults)
        manager.selectVehicle(vehicle)
        XCTAssertTrue(manager.selectedProfile is MercedesEQAOBDbProfile)
        XCTAssertEqual(VehicleDataManager(userDefaults: defaults).selectedVehicle.id, vehicle.id)
        XCTAssertTrue(profile.initializationCommands.contains("AT SP 6"))
        XCTAssertEqual(Array(profile.pollingCommands.prefix(5)), ["AT CRA 7EA", "AT SH 7E2", "222001", "AT CRA 7ED", "AT SH 7E5"])

        let timestamp = Date()
        for (command, response) in [
            ("222001", "7EA 10 0B 62 20 01 00 00 00\r7EA 21 00 00 00 00 00 00 00"),
            ("226050", "7ED 05 62 60 50 1F A4"),
            ("226075", "7ED 05 62 60 75 3E 80"),
            ("226053", "7ED 05 62 60 53 FC 18")
        ] {
            XCTAssertTrue(manager.applyUpdates(profile.parseResponses(command: command, rawResponse: response), timestamp: timestamp))
        }
        XCTAssertEqual(manager.latestTelemetry.chargePowerKW, 40, accuracy: 0.001)
        XCTAssertTrue(manager.latestTelemetry.isCharging)
        XCTAssertTrue(manager.hasChargePower)
        XCTAssertFalse(manager.liveMetrics.contains(.batteryTemp))
        // Without fresh stationary speed, negative current cannot establish charging.
        manager.applyUpdates(profile.parseResponses(command: "226053", rawResponse: "7ED 05 62 60 53 FC 18"), timestamp: timestamp.addingTimeInterval(60))
        XCTAssertFalse(manager.latestTelemetry.isCharging)
    }
}
