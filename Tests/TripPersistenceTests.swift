import XCTest
import SwiftData
import Combine
@testable import VoltLinkEngine

final class TripPersistenceTests: XCTestCase {

    @MainActor
    func testDemoRecordsAreTransientAndWipedOnExitWithoutDeletingRealHistory() throws {
        let env = AppEnvironment(modelContainer: container)
        env.tripTracker.isAutoTripEnabled = false
        env.tripTracker.startTrip(startSoc: 80)
        let realTripID = try XCTUnwrap(env.tripTracker.currentTrip?.id)
        env.chargingTracker.startSession(startSoc: 20)
        let realChargeID = try XCTUnwrap(env.chargingTracker.currentSession?.id)
        env.vehicleData.toggleDemoMode(true)
        (env.vehicleData.obdConnection as? MockOBDAdapter)?.simulationEngine.stop()

        env.tripTracker.startTrip(startSoc: 70)
        env.tripTracker.stopTrip(endSoc: 60)
        env.chargingTracker.startSession(startSoc: 30)
        env.chargingTracker.stopSession(endSoc: 50)
        XCTAssertEqual(env.tripTracker.demoTrips.count, 1)
        XCTAssertEqual(env.chargingTracker.demoSessions.count, 1)
        env.tripTracker.clearAllTrips()
        env.chargingTracker.clearAllSessions()
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<TripModel>()).map(\.id), [realTripID])
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ChargingSessionModel>()).map(\.id), [realChargeID])

        env.tripTracker.startTrip()
        env.tripTracker.stopTrip()
        env.chargingTracker.startSession()
        env.chargingTracker.stopSession()
        env.tripTracker.startTrip() // Also discard active demo records on exit.
        env.chargingTracker.startSession()
        env.vehicleData.toggleDemoMode(false)
        XCTAssertTrue(env.tripTracker.demoTrips.isEmpty)
        XCTAssertTrue(env.chargingTracker.demoSessions.isEmpty)
        XCTAssertNil(env.tripTracker.currentTrip)
        XCTAssertNil(env.chargingTracker.currentSession)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<TripModel>()), 1)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ChargingSessionModel>()), 1)
    }

    @MainActor
    func testFailedSaveRetainsRecordingAndBlocksDemoSwitch() throws {
        let configuration = ModelConfiguration(schema: container.schema,
            url: storeDirectory.appendingPathComponent("trips.store"), allowsSave: false)
        let readOnly = try ModelContainer(for: container.schema, configurations: configuration)
        let env = AppEnvironment(modelContainer: readOnly)
        env.tripTracker.isAutoTripEnabled = false
        env.tripTracker.startTrip()
        let trip = try XCTUnwrap(env.tripTracker.currentTrip)
        XCTAssertNotNil(env.tripTracker.persistenceError)
        XCTAssertFalse(env.tripTracker.stopTrip())
        XCTAssertTrue(env.tripTracker.currentTrip === trip)
        env.vehicleData.toggleDemoMode(true)
        XCTAssertFalse(env.vehicleData.isDemoMode)
        XCTAssertFalse(env.tripTracker.isDemoMode)
        XCTAssertFalse(env.chargingTracker.isDemoMode)
        XCTAssertFalse(env.tripTracker.locationManager.tripTrackingRequested)

        env.chargingTracker.startSession()
        let session = try XCTUnwrap(env.chargingTracker.currentSession)
        XCTAssertFalse(env.chargingTracker.stopSession())
        XCTAssertTrue(env.chargingTracker.currentSession === session)
        XCTAssertNotNil(env.chargingTracker.persistenceError)
    }

    func testDeletingOrClearingActiveTripReleasesGPSRequest() throws {
        let tracker = TripTrackingManager()
        tracker.startTrip()
        XCTAssertTrue(tracker.locationManager.tripTrackingRequested)
        tracker.deleteTrip(try XCTUnwrap(tracker.currentTrip))
        XCTAssertFalse(tracker.locationManager.tripTrackingRequested)
        tracker.startTrip()
        tracker.clearAllTrips()
        XCTAssertFalse(tracker.locationManager.tripTrackingRequested)
    }
    private var storeDirectory: URL!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        storeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let schema = Schema([TripModel.self, TelemetryPointModel.self, ChargingSessionModel.self])
        let configuration = ModelConfiguration(schema: schema, url: storeDirectory.appendingPathComponent("trips.store"))
        container = try ModelContainer(for: schema, configurations: configuration)
    }

    override func tearDownWithError() throws {
        container = nil
        if let storeDirectory {
            try FileManager.default.removeItem(at: storeDirectory)
        }
    }

    @MainActor
    func testMergePreservesPersistedSamplesAndDeleteStillCascades() throws {
        // Exercise both insertion orders repeatedly: relationship saves previously
        // lost the destination link intermittently while leaving the sample row intact.
        for _ in 0..<10 {
            try checkMergeAndCascade(insertNewerFirst: false)
            try checkMergeAndCascade(insertNewerFirst: true)
        }
    }

    @MainActor
    private func checkMergeAndCascade(insertNewerFirst: Bool) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let tracker = TripTrackingManager()
        tracker.modelContext = context
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let older = TripModel(startTime: start, distanceKm: 10, startSocPct: 90)
        older.endTime = start.addingTimeInterval(600)
        older.totalKWhUsed = 2
        older.maxPowerKW = 35
        older.maxRegenKW = -5
        older.samples = [
            TelemetryPointModel(timestamp: start.addingTimeInterval(100), latitude: 52.1, longitude: 13.1, speedKmH: 40, powerKW: -5, socPct: 89, batteryTempC: 26),
            TelemetryPointModel(timestamp: start, latitude: 52, longitude: 13, speedKmH: 30, powerKW: 35, socPct: 90, batteryTempC: 25)
        ]
        let newer = TripModel(startTime: start.addingTimeInterval(900), distanceKm: 5, startSocPct: 85)
        let end = start.addingTimeInterval(1200)
        newer.endTime = end
        newer.endSocPct = 82
        newer.totalKWhUsed = 1
        newer.maxPowerKW = 45
        newer.maxRegenKW = -10
        newer.samples = [
            TelemetryPointModel(timestamp: end, latitude: 53.1, longitude: 14.1, speedKmH: 20, powerKW: -10, socPct: 82, batteryTempC: 28),
            TelemetryPointModel(timestamp: newer.startTime, latitude: 53, longitude: 14, speedKmH: 60, powerKW: 45, socPct: 85, batteryTempC: 27)
        ]
        for trip in insertNewerFirst ? [newer, older] : [older, newer] {
            context.insert(trip)
        }
        try context.save()
        let tripID = older.id
        let olderIDs = Set(older.samples.map(\.persistentModelID))
        let newerIDs = Set(newer.samples.map(\.persistentModelID))
        let expectedValues = sampleValues(older.samples + newer.samples)
        XCTAssertEqual(expectedValues.count, 4)
        var saveCount = 0
        let saveObserver = NotificationCenter.default.publisher(for: ModelContext.didSave, object: context)
            .sink { _ in saveCount += 1 }
        defer { saveObserver.cancel() }

        tracker.merge(newer, into: older)

        XCTAssertEqual(saveCount, 1)
        let mergedIDs = Set(older.samples.map(\.persistentModelID))
        XCTAssertEqual(mergedIDs.count, 4)
        XCTAssertTrue(olderIDs.isSubset(of: mergedIDs))
        XCTAssertTrue(newerIDs.isDisjoint(with: mergedIDs))
        XCTAssertEqual(sampleValues(older.samples), expectedValues)

        // Read the saved store, not the merging context's cached relationship objects.
        let verificationContext = ModelContext(container)
        verificationContext.autosaveEnabled = false
        let trips = try verificationContext.fetch(FetchDescriptor<TripModel>())
        XCTAssertEqual(trips.count, 1)
        let merged = try XCTUnwrap(trips.first)
        XCTAssertEqual(merged.id, tripID)
        XCTAssertEqual(merged.distanceKm, 15)
        XCTAssertEqual(merged.totalKWhUsed, 3)
        XCTAssertEqual(merged.maxPowerKW, 45)
        XCTAssertEqual(merged.maxRegenKW, -10)
        XCTAssertEqual(merged.endTime, end)
        XCTAssertEqual(merged.endSocPct, 82)
        XCTAssertEqual(Set(merged.samples.map(\.persistentModelID)), mergedIDs)
        XCTAssertEqual(sampleValues(merged.samples), expectedValues)
        let savedSamples = try verificationContext.fetch(FetchDescriptor<TelemetryPointModel>())
        XCTAssertEqual(savedSamples.count, 4)
        XCTAssertEqual(Set(savedSamples.map(\.persistentModelID)), mergedIDs)
        XCTAssertEqual(sampleValues(savedSamples), expectedValues)

        let notification = expectation(forNotification: Notification.Name("DeleteTripNotification"), object: nil) {
            $0.object as? UUID == tripID
        }
        tracker.modelContext = verificationContext
        tracker.deleteTrip(merged)
        wait(for: [notification], timeout: 1)

        let deletionContext = ModelContext(container)
        XCTAssertEqual(try deletionContext.fetchCount(FetchDescriptor<TripModel>()), 0)
        XCTAssertEqual(try deletionContext.fetchCount(FetchDescriptor<TelemetryPointModel>()), 0)
    }

    private func sampleValues(_ samples: [TelemetryPointModel]) -> [[Double]] {
        samples.sorted { $0.timestamp < $1.timestamp }.map {
            [$0.timestamp.timeIntervalSince1970, $0.latitude, $0.longitude,
             $0.speedKmH, $0.powerKW, $0.socPct, $0.batteryTempC]
        }
    }

    @MainActor
    func testFailedMergeRestoresTripsWithoutDiscardingUnrelatedEdits() throws {
        try checkFailedMerge(useExistingUndoManager: false)
    }

    @MainActor
    func testFailedMergePreservesExistingUndoGroup() throws {
        try checkFailedMerge(useExistingUndoManager: true)
    }

    @MainActor
    private func checkFailedMerge(useExistingUndoManager: Bool) throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let context = ModelContext(container)
        let older = TripModel(startTime: start, distanceKm: 10, startSocPct: 90)
        older.endTime = start.addingTimeInterval(600)
        older.endSocPct = 85
        older.totalKWhUsed = 2
        older.maxPowerKW = 35
        older.maxRegenKW = -5
        older.samples = [TelemetryPointModel(timestamp: start, speedKmH: 30)]
        let newer = TripModel(startTime: start.addingTimeInterval(900), distanceKm: 5)
        newer.endTime = start.addingTimeInterval(1200)
        newer.endSocPct = 82
        newer.totalKWhUsed = 1
        newer.maxPowerKW = 45
        newer.maxRegenKW = -10
        newer.samples = [TelemetryPointModel(timestamp: newer.startTime, speedKmH: 60)]
        let unrelated = ChargingSessionModel(locationName: "Original")
        context.insert(older)
        context.insert(newer)
        context.insert(unrelated)
        try context.save()

        let configuration = ModelConfiguration(schema: container.schema,
                                             url: storeDirectory.appendingPathComponent("trips.store"), allowsSave: false)
        let readOnlyContainer = try ModelContainer(for: container.schema, configurations: configuration)
        let readOnlyContext = ModelContext(readOnlyContainer)
        readOnlyContext.autosaveEnabled = false
        let undoManager = useExistingUndoManager ? UndoManager() : nil
        undoManager?.groupsByEvent = false
        readOnlyContext.undoManager = undoManager
        let trips = try readOnlyContext.fetch(FetchDescriptor<TripModel>(sortBy: [SortDescriptor(\.startTime)]))
        let source = trips[1]
        let destination = trips[0]
        let tripIDs = Set(trips.map(\.persistentModelID))
        let originalIDs = Set(trips.flatMap(\.samples).map(\.persistentModelID))
        let originalValues = sampleValues(trips.flatMap(\.samples))
        let pendingSession = try XCTUnwrap(readOnlyContext.fetch(FetchDescriptor<ChargingSessionModel>()).first)
        undoManager?.beginUndoGrouping()
        pendingSession.locationName = "Pending edit"
        destination.distanceKm = 12 // A pre-existing edit on a merged model must survive too.
        let tracker = TripTrackingManager()
        tracker.modelContext = readOnlyContext

        tracker.merge(source, into: destination)

        XCTAssertFalse(source.isDeleted)
        XCTAssertFalse(destination.isDeleted)
        XCTAssertEqual(Set(trips.map(\.persistentModelID)), tripIDs)
        XCTAssertEqual(destination.distanceKm, 12)
        XCTAssertEqual(destination.totalKWhUsed, 2)
        XCTAssertEqual(destination.maxPowerKW, 35)
        XCTAssertEqual(destination.maxRegenKW, -5)
        XCTAssertEqual(destination.endTime, start.addingTimeInterval(600))
        XCTAssertEqual(destination.endSocPct, 85)
        XCTAssertEqual(destination.samples.count, 1)
        XCTAssertEqual(source.samples.count, 1)
        XCTAssertEqual(Set(trips.flatMap(\.samples).map(\.persistentModelID)), originalIDs)
        XCTAssertEqual(sampleValues(trips.flatMap(\.samples)), originalValues)
        XCTAssertTrue(trips.flatMap(\.samples).allSatisfy { !$0.isDeleted })
        XCTAssertEqual(pendingSession.locationName, "Pending edit")
        XCTAssertEqual(try readOnlyContext.fetch(FetchDescriptor<TripModel>()).count, 2)
        XCTAssertTrue(readOnlyContext.deletedModelsArray.isEmpty)
        XCTAssertEqual(try readOnlyContext.fetchCount(FetchDescriptor<TripModel>()), 2)
        XCTAssertEqual(try readOnlyContext.fetchCount(FetchDescriptor<TelemetryPointModel>()), 2)
        let verificationContext = ModelContext(container)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<TripModel>()), 2)
        XCTAssertEqual(sampleValues(try verificationContext.fetch(FetchDescriptor<TelemetryPointModel>())), originalValues)
        XCTAssertEqual(try verificationContext.fetch(FetchDescriptor<ChargingSessionModel>()).first?.locationName, "Original")
        XCTAssertTrue(readOnlyContext.undoManager === undoManager)
        if let undoManager {
            undoManager.endUndoGrouping()
            undoManager.undo()
            XCTAssertEqual(pendingSession.locationName, "Original")
            XCTAssertEqual(destination.distanceKm, 10)
            XCTAssertFalse(source.isDeleted)
            XCTAssertEqual(try readOnlyContext.fetchCount(FetchDescriptor<TripModel>()), 2)
            XCTAssertEqual(try readOnlyContext.fetchCount(FetchDescriptor<TelemetryPointModel>()), 2)
        }
    }

    @MainActor
    func testDeleteChargingSessionPostsCapturedIDAndPersistsDeletion() throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let tracker = ChargingTrackingManager()
        tracker.modelContext = context
        tracker.startSession(startSoc: 20)
        let session = try XCTUnwrap(tracker.currentSession)
        let sessionID = session.id
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ChargingSessionModel>()), 1)
        let notification = expectation(forNotification: Notification.Name("DeleteChargingSessionNotification"), object: nil) {
            $0.object as? UUID == sessionID
        }

        tracker.deleteSession(session)

        wait(for: [notification], timeout: 1)
        XCTAssertNil(tracker.currentSession)
        XCTAssertFalse(tracker.isRecordingSession)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ChargingSessionModel>()), 0)
    }
}
