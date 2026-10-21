import XCTest
import SwiftData
@testable import VoltLinkEngine

/// Guards the upgrade path for stores written by a previous build by opening a V1
/// container's store with the current versioned schema.
///
/// The fixture is written with today's model classes, so it cannot reproduce a
/// relationship that only exists in the newer class definitions. A future change that
/// renames or removes a persisted property still needs legacy model copies in its own
/// fixture to be covered here.
final class SchemaMigrationTests: XCTestCase {
    func testV1StoreMigratesToCurrentSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("v1.store")
        let tripID = UUID()

        autoreleasepool {
            let v1 = Schema(versionedSchema: VoltLinkSchemaV1.self)
            do {
                let container = try ModelContainer(for: v1, configurations: ModelConfiguration(schema: v1, url: url))
                let context = ModelContext(container)
                let trip = TripModel(id: tripID, startTime: Date(timeIntervalSince1970: 1_700_000_000), distanceKm: 12, startSocPct: 80)
                trip.endTime = trip.startTime.addingTimeInterval(600)
                trip.samples = [TelemetryPointModel(timestamp: trip.startTime, speedKmH: 50)]
                context.insert(trip)
                try context.save()
            } catch {
                XCTFail("Could not create the V1 store: \(error)")
            }
        }

        let current = Schema(versionedSchema: VoltLinkCurrentSchema.versioned)
        let container = try ModelContainer(for: current, configurations: ModelConfiguration(schema: current, url: url))
        let context = ModelContext(container)
        let trips = try context.fetch(FetchDescriptor<TripModel>())
        XCTAssertEqual(trips.map(\.id), [tripID], "Existing trips survive the schema upgrade")
        XCTAssertEqual(trips.first?.samples.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChargingSessionModel>()), 0)
    }
}
