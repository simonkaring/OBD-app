import XCTest
@testable import VoltLinkEngine

final class ABRPProfileLoaderTests: XCTestCase {
    func testLoadBundledProfiles() {
        let profiles = ABRPProfileLoader.loadBundledProfiles()
        XCTAssertFalse(profiles.isEmpty, "Should load bundled ABRP PID profiles")
        
        let names = profiles.map { $0.vehicleName }
        XCTAssertTrue(names.contains(where: { $0.contains("Volkswagen") }))
        XCTAssertTrue(names.contains(where: { $0.contains("Ford") }))
        XCTAssertTrue(names.contains(where: { $0.contains("Hyundai") }))
    }

    func testDynamicABRPEvaluation() {
        let jsonStr = """
        {
            "init_commands": { "command": ["ATZ", "ATSP6"] },
            "data_commands": { "command": ["220101", "220105"] },
            "soc": {
                "equation": "A*0.5",
                "command": "220105"
            },
            "voltage": {
                "equation": "((A*256)+B)*0.1",
                "command": "220101"
            }
        }
        """
        guard let data = jsonStr.data(using: .utf8),
              let def = try? JSONDecoder().decode(ABRPProfileDefinition.self, from: data) else {
            XCTFail("Failed to decode test ABRP definition")
            return
        }

        let profile = ABRPGenericVehicleProfile(name: "Test Vehicle", capacityKWh: 75.0, definition: def)
        XCTAssertEqual(profile.initializationCommands, ["ATZ", "ATSP6"])
        XCTAssertEqual(profile.pollingCommands, ["220101", "220105"])

        // Test SOC: 62 01 05 [C8] -> A = 200 -> 200 * 0.5 = 100.0%
        let socUpdate = profile.parseResponse(command: "220105", rawResponse: "62 01 05 C8")
        guard case .soc(let socVal)? = socUpdate else {
            XCTFail("Expected .soc update, got \(String(describing: socUpdate))")
            return
        }
        XCTAssertEqual(socVal, 100.0)

        // Test Voltage: 62 01 01 [0E 74] -> (14*256 + 116) = 3700 -> 370.0 V
        let voltUpdate = profile.parseResponse(command: "220101", rawResponse: "62 01 01 0E 74")
        guard case .packVoltage(let voltVal)? = voltUpdate else {
            XCTFail("Expected .packVoltage update, got \(String(describing: voltUpdate))")
            return
        }
        XCTAssertEqual(voltVal, 370.0, accuracy: 0.1)
    }

    func testVehicleCatalogDataDrivenLoading() {
        XCTAssertFalse(VehicleCatalog.brands.isEmpty, "Catalog brands should not be empty")
        XCTAssertGreaterThan(VehicleCatalog.allModels.count, 20, "Should load many vehicles from dataset")
        XCTAssertEqual(VehicleCatalog.dataSource, "OpenEV Data Dataset & Iternio EV-OBD-PIDs")

        let brands = VehicleCatalog.brands.map { $0.name }
        XCTAssertTrue(brands.contains("Tesla"))
        XCTAssertTrue(brands.contains("Mercedes-Benz"))
        XCTAssertTrue(brands.contains("Hyundai"))
        XCTAssertTrue(brands.contains("Volkswagen"))
        XCTAssertFalse(VehicleCatalog.allModels.contains { $0.batteryCapacityKWh == 0 })
        XCTAssertEqual(VehicleCatalog.allModels.first { $0.id == "mb-eqa-250" }?.batteryCapacityKWh, 66.5)
    }
}
