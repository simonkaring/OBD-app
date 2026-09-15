import XCTest
@testable import VoltLinkEngine

final class VehicleCatalogSelectionTests: XCTestCase {
    func testExplicitFamilyMetadataGroupsSelectableLeaves() {
        let standard = makeVehicle(
            id: "test-standard",
            modelName: "Example Standard",
            familyID: "example",
            familyName: "Example",
            variantName: "Standard"
        )
        let longRange = makeVehicle(
            id: "test-long-range",
            modelName: "Example Long Range",
            familyID: "example",
            familyName: "Example",
            variantName: "Long Range"
        )

        let families = VehicleCatalog.modelFamilies(for: [standard, longRange])

        XCTAssertEqual(families.count, 1)
        XCTAssertEqual(families[0].id, "example")
        XCTAssertEqual(families[0].name, "Example")
        XCTAssertEqual(Set(families[0].variants.map(\.id)), ["test-standard", "test-long-range"])
    }

    func testLegacyGroupingUsesModelMetadataWithoutParsingLeafIDs() {
        let older = makeVehicle(id: "unrelated-alpha", modelName: "Legacy Model", years: "2020")
        let newer = makeVehicle(id: "different-beta", modelName: "legacy model", years: "2021")

        let families = VehicleCatalog.modelFamilies(for: [newer, older])

        XCTAssertEqual(families.count, 1)
        XCTAssertEqual(families[0].id, "legacy:different-beta")
        XCTAssertEqual(Set(families[0].variants.map(\.id)), ["unrelated-alpha", "different-beta"])
    }

    func testSelectedLeafIDRestoresVehicleAndProfile() throws {
        let suiteName = "VehicleCatalogSelectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let selected = try XCTUnwrap(VehicleCatalog.allModels.first { $0.id != VehicleCatalog.defaultModel.id })

        let firstManager = VehicleDataManager(userDefaults: defaults)
        firstManager.selectVehicle(selected)
        let restoredManager = VehicleDataManager(userDefaults: defaults)

        XCTAssertEqual(defaults.string(forKey: VehicleDataManager.selectedVehicleIDDefaultsKey), selected.id)
        XCTAssertEqual(restoredManager.selectedVehicle.id, selected.id)
        XCTAssertEqual(restoredManager.selectedProfileID, selected.profileID)
        XCTAssertEqual(restoredManager.selectedProfile.vehicleName, selected.profileID.makeProfile().vehicleName)
    }

    func testCatalogYearLabelsPreserveRangesGapsAndExperimentalYear() {
        for (label, expected) in [
            ("2021", [2021]),
            ("2021 · experimental", [2021]),
            ("2017-2019", [2019, 2018, 2017]),
            ("2023, 2025", [2025, 2023]),
            ("2020–2021, 2023-2024", [2024, 2023, 2021, 2020]),
            ("2024+", [2026, 2025, 2024]),
            ("2025-2023", []),
            ("unknown", []),
            ("2023, invalid", [])
        ] {
            XCTAssertEqual(makeVehicle(id: "test", modelName: "Test", years: label).modelYears(through: 2026), expected, label)
        }
        for vehicle in VehicleCatalog.allModels {
            XCTAssertFalse(vehicle.modelYears().isEmpty, "Unrecognized catalog years: \(vehicle.id): \(vehicle.years)")
        }
    }

    func testYearFilteringKeepsOnlyMatchingVariantsAndTheirProfiles() throws {
        let older = makeVehicle(id: "older", modelName: "Example", years: "2020-2021", profileID: .genericOBD2)
        let newer = makeVehicle(id: "newer", modelName: "Example", years: "2023, 2025", profileID: .genericEV)
        let family = try XCTUnwrap(VehicleCatalog.modelFamilies(for: [older, newer]).first)
        XCTAssertEqual(family.modelYears, [2025, 2023, 2021, 2020])
        XCTAssertEqual(family.variants(forModelYear: 2021).map(\.profileID), [.genericOBD2])
        XCTAssertEqual(family.variants(forModelYear: 2025).map(\.profileID), [.genericEV])
        XCTAssertTrue(family.variants(forModelYear: 2024).isEmpty)

        let eqaFamily = try XCTUnwrap(VehicleCatalog.modelFamilies(for: [VehicleCatalog.defaultModel, VehicleCatalog.eqaOBDbModel]).first)
        XCTAssertEqual(eqaFamily.modelYears, [2021])
        XCTAssertEqual(Set(eqaFamily.variants(forModelYear: 2021).map(\.profileID)), [.mercedesEQA250, .mercedesEQAOBDb])
    }

    @MainActor
    func testSelectedModelYearRestoresAndFlowsIntoCaptureContext() throws {
        let suiteName = "VehicleModelYearTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let vehicle = VehicleCatalog.eqaOBDbModel
        let manager = VehicleDataManager(userDefaults: defaults)
        XCTAssertTrue(manager.selectVehicle(vehicle, modelYear: 2021))
        XCTAssertEqual(defaults.integer(forKey: VehicleDataManager.selectedModelYearDefaultsKey), 2021)

        let restored = VehicleDataManager(userDefaults: defaults)
        XCTAssertEqual(restored.selectedVehicle.id, vehicle.id)
        XCTAssertEqual(restored.selectedModelYear, 2021)
        XCTAssertTrue(restored.selectedProfile is MercedesEQAOBDbProfile)
        XCTAssertEqual(restored.vehicleName, "Mercedes-Benz EQA 250 (OBDb community) (2021)")

        // The capture UI passes vehicleName as its context; exercise the actual file header.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bluetooth = BluetoothManager(commandWriter: { _ in }, scheduleRecovery: { _ in }, captureDirectory: directory)
        bluetooth.startCapture(vehicleContext: restored.vehicleName)
        bluetooth.stopCapture()
        let capture = try String(contentsOf: XCTUnwrap(bluetooth.captureFileURL), encoding: .utf8)
        XCTAssertTrue(capture.contains("# Vehicle: \(restored.vehicleName)"))

        // Invalid selections must not change the current vehicle, profile, or saved year.
        XCTAssertFalse(restored.selectVehicle(VehicleCatalog.defaultModel, modelYear: 2024))
        XCTAssertEqual(restored.selectedVehicle.id, vehicle.id)
        XCTAssertEqual(restored.selectedModelYear, 2021)
        XCTAssertEqual(defaults.integer(forKey: VehicleDataManager.selectedModelYearDefaultsKey), 2021)

        XCTAssertTrue(restored.selectVehicle(VehicleCatalog.defaultModel))
        XCTAssertNil(restored.selectedModelYear)
        XCTAssertNil(defaults.object(forKey: VehicleDataManager.selectedModelYearDefaultsKey))
    }

    func testLegacySelectionAndInvalidSavedYearDoNotInventModelYear() throws {
        let suiteName = "VehicleModelYearMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(VehicleCatalog.eqaOBDbModel.id, forKey: VehicleDataManager.selectedVehicleIDDefaultsKey)
        let legacy = VehicleDataManager(userDefaults: defaults)
        XCTAssertEqual(legacy.selectedVehicle.id, VehicleCatalog.eqaOBDbModel.id)
        XCTAssertNil(legacy.selectedModelYear)
        defaults.set(2024, forKey: VehicleDataManager.selectedModelYearDefaultsKey)
        let invalid = VehicleDataManager(userDefaults: defaults)
        XCTAssertEqual(invalid.selectedVehicle.id, VehicleCatalog.eqaOBDbModel.id)
        XCTAssertNil(invalid.selectedModelYear)
    }

    func testHasSelectedVehicleIsFalseForANewManagerWithNoSavedSelection() throws {
        let suiteName = "HasSelectedVehicleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = VehicleDataManager(userDefaults: defaults)
        XCTAssertFalse(manager.hasSelectedVehicle)
    }

    func testHasSelectedVehicleRestoresOnlyFromAValidSavedVehicleID() throws {
        let suiteName = "HasSelectedVehicleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("not-a-real-vehicle-id", forKey: VehicleDataManager.selectedVehicleIDDefaultsKey)
        let invalid = VehicleDataManager(userDefaults: defaults)
        XCTAssertFalse(invalid.hasSelectedVehicle, "An unrecognized saved ID must not count as a selection")

        let vehicle = try XCTUnwrap(VehicleCatalog.allModels.first { $0.id != VehicleCatalog.defaultModel.id })
        defaults.set(vehicle.id, forKey: VehicleDataManager.selectedVehicleIDDefaultsKey)
        let valid = VehicleDataManager(userDefaults: defaults)
        XCTAssertTrue(valid.hasSelectedVehicle)
        XCTAssertEqual(valid.selectedVehicle.id, vehicle.id)
    }

    func testHasSelectedVehicleIsSetBySelectVehicleAndNotByDemoMode() throws {
        let suiteName = "HasSelectedVehicleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = VehicleDataManager(userDefaults: defaults)
        XCTAssertFalse(manager.hasSelectedVehicle)

        manager.toggleDemoMode(true)
        XCTAssertFalse(manager.hasSelectedVehicle, "Enabling demo mode must not count as choosing a vehicle")
        manager.toggleDemoMode(false)
        XCTAssertFalse(manager.hasSelectedVehicle)

        manager.selectVehicle(VehicleCatalog.eqaOBDbModel)
        XCTAssertTrue(manager.hasSelectedVehicle)
    }

    func testGenericEVModelHasUnknownCapacityAndRangeAndIsRestorableFromTheCatalog() throws {
        XCTAssertEqual(VehicleCatalog.genericEVModel.batteryCapacityKWh, 0, "Generic EV capacity is unknown until a real vehicle is picked")
        XCTAssertNil(VehicleCatalog.genericEVModel.estimatedRangeKm)
        XCTAssertEqual(VehicleCatalog.genericEVModel.profileID, .genericEV)

        // The catalog must always carry an entry for this ID so a saved selection of it restores.
        XCTAssertTrue(VehicleCatalog.allModels.contains { $0.id == VehicleCatalog.genericEVModel.id })

        let suiteName = "HasSelectedVehicleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(VehicleCatalog.genericEVModel.id, forKey: VehicleDataManager.selectedVehicleIDDefaultsKey)

        let restored = VehicleDataManager(userDefaults: defaults)
        XCTAssertTrue(restored.hasSelectedVehicle)
        XCTAssertEqual(restored.selectedVehicle.id, VehicleCatalog.genericEVModel.id)
        XCTAssertEqual(restored.selectedProfileID, .genericEV)
        XCTAssertEqual(restored.usableBatteryCapacityKWh, 0)
        XCTAssertNil(restored.estimatedFullRangeKm)
    }

    func testSharedDecoderDoesNotInventSpecificationsForSelectedVariant() {
        let vehicle = VehicleModelEntry(id: "unknown-meb", brandName: "Volkswagen", modelName: "Unknown variant", years: "2025", powertrain: .ev, batteryCapacityKWh: 0, profileID: .volkswagenMEB)
        let manager = VehicleDataManager()
        manager.selectVehicle(vehicle)
        XCTAssertEqual(manager.usableBatteryCapacityKWh, 0)
        XCTAssertNil(manager.estimatedFullRangeKm)
    }

    private func makeVehicle(
        id: String,
        modelName: String,
        years: String = "2025+",
        profileID: VehicleProfileID = .genericEV,
        familyID: String? = nil,
        familyName: String? = nil,
        variantName: String? = nil
    ) -> VehicleModelEntry {
        VehicleModelEntry(
            id: id,
            brandName: "Test",
            modelName: modelName,
            years: years,
            powertrain: .ev,
            batteryCapacityKWh: 70,
            profileID: profileID,
            modelFamilyID: familyID,
            modelFamilyName: familyName,
            variantDisplayName: variantName
        )
    }
}
