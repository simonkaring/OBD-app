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

    /// Regression test for the fix that routes ABRP responses through
    /// `ISO15765Parser.assembleISOTPPayload` first: a genuinely multi-frame reply (First
    /// Frame + Consecutive Frame) must decode to the same value as the equivalent single-frame
    /// reply, instead of reading garbage bytes from the interleaved CAN ID / PCI bytes.
    func testABRPDecodesMultiFrameReplyIdenticallyToSingleFrame() throws {
        let machE = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "ford_MachE.json"))

        // First Frame (10 0A = total 10 data bytes: 62 48 F9 FF 9C 00 00 00 00 00),
        // Consecutive Frame (21) carries the tail, including trailing pad past the declared
        // length. The current DID formula only reads bytes A/B (= FF 9C), matching the
        // single-frame fixture used in `testABRPCurrentUsesMeasuredVoltageNotNominal`.
        let raw = "7E8 10 0A 62 48 F9 FF\r\n7E8 21 9C 00 00 00 00 00\r\n>"
        guard case .packCurrent(let amps)? = machE.parseResponse(command: "2248F9", rawResponse: raw) else {
            return XCTFail("Expected .packCurrent from multi-frame reply")
        }
        XCTAssertEqual(amps, -10.0, accuracy: 0.01)
    }

    /// `signed()` must work when embedded inside a larger arithmetic expression, not just as
    /// a bare wrapper — matches the E-GMP `current` formula, which nests it two levels deep.
    func testABRPSignedFunctionInsideLargerExpression() throws {
        let ioniq5 = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "hkmc_Ioniq5.json"))
        // Equation: ((Signed(K)*256)+L)/10. K = byte index 10, L = byte index 11.
        // K = 0xFF (-1 signed), L = 0x9C (156) -> ((-1*256)+156)/10 = -10.0
        let raw = "62 01 01 00 00 00 00 00 00 00 00 00 00 FF 9C\r\n>"
        guard case .packCurrent(let amps)? = ioniq5.parseResponse(command: "220101", rawResponse: raw) else {
            return XCTFail("Expected .packCurrent update")
        }
        XCTAssertEqual(amps, -10.0, accuracy: 0.01)
    }

    /// Verifies the new BMW i3 (copied from the Mini profile's BMW SME battery module family,
    /// with only the voltage range widened) and Deepal S05 (candidate PIDs normalized into the
    /// ABRP definition format) profiles both load and decode correctly.
    func testBMWi3AndDeepalProfilesLoadAndDecode() throws {
        let i3 = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "bmw_i3.json"))
        let i3Raw = "607 05 62 DD BC 02 EE\r\n>"
        guard case .soc(let i3Soc)? = i3.parseResponse(command: "22DDBC", rawResponse: i3Raw) else {
            return XCTFail("Expected .soc update from BMW i3 profile")
        }
        XCTAssertEqual(i3Soc, 75.0, accuracy: 0.01)

        let deepal = try XCTUnwrap(ABRPProfileLoader.loadProfile(filename: "deepal_s05.json"))
        let deepalRaw = "7A9 05 62 F2 28 0F A0\r\n>"
        guard case .packVoltage(let deepalVoltage)? = deepal.parseResponse(command: "22F228", rawResponse: deepalRaw) else {
            return XCTFail("Expected .packVoltage update from Deepal S05 profile")
        }
        XCTAssertEqual(deepalVoltage, 400.0, accuracy: 0.01)
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
        XCTAssertTrue(brands.contains("Zeekr"))
        XCTAssertEqual(VehicleCatalog.allModels.first { $0.id == "mb-eqa-250" }?.batteryCapacityKWh, 66.5)
        XCTAssertEqual(VehicleCatalog.allModels.first { $0.id == "zeekr-7x-100" }?.batteryCapacityKWh, 100.0)

        // Alphabetical sorting test
        let sortedBrandNames = brands.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        XCTAssertEqual(brands, sortedBrandNames, "Vehicle catalog brands should be sorted alphabetically")

        for brand in VehicleCatalog.brands {
            let modelNames = brand.models.map { $0.modelName }
            let sortedModelNames = modelNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            XCTAssertEqual(modelNames, sortedModelNames, "Models for brand \(brand.name) should be sorted alphabetically")
        }
    }
}
