import Foundation
import SwiftData
import XCTest

@testable import VoltLinkEngine

/// The entity V1–V3 shipped but nothing ever wrote. Recreated here so a store written by the
/// previous build can be simulated after the model was removed from the app.
@Model
final class SavedDTCModel {
    var id: UUID = UUID()
    var scanDate: Date = Date()
    var code: String = ""
    var title: String = ""
    var category: String = ""
    var severityRaw: String = ""
    var freezeFrameSummary: String = ""

    init() {}
}

/// Removing the never-written `SavedDTCModel` must stay a lightweight migration: an existing
/// store carries the empty entity, and the current schema no longer describes it.
final class LegacySavedDTCStoreTests: XCTestCase {
    @MainActor
    func testStoreWrittenWithTheDroppedEntityStillOpens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")

        let legacy = Schema([
            TripModel.self, TelemetryPointModel.self, ChargingSessionModel.self,
            ChargingSampleModel.self, BatteryHealthSampleModel.self, SavedDTCModel.self,
        ])
        do {
            let container = try ModelContainer(for: legacy, configurations: ModelConfiguration(schema: legacy, url: url))
            let context = ModelContext(container)
            context.insert(TripModel(startTime: .now, distanceKm: 5, startSocPct: 50))
            context.insert(SavedDTCModel())
            try context.save()
        }

        let current = Schema(versionedSchema: VoltLinkCurrentSchema.versioned)
        let container = try ModelContainer(for: current, configurations: ModelConfiguration(schema: current, url: url))
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TripModel>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChargingSessionModel>()), 0)
    }
}
