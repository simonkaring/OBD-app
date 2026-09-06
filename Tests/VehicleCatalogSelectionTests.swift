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

    private func makeVehicle(
        id: String,
        modelName: String,
        years: String = "2025+",
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
            profileID: .genericEV,
            modelFamilyID: familyID,
            modelFamilyName: familyName,
            variantDisplayName: variantName
        )
    }
}
