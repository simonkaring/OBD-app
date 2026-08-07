import XCTest
@testable import VoltLinkEngine

final class TripAndTelemetryTests: XCTestCase {

    func testTripModelSampleAccumulationAndEfficiency() {
        let trip = TripModel(startTime: Date(), distanceKm: 10.0, startSocPct: 90.0, vehicleName: "Mercedes EQA 250")
        trip.endSocPct = 85.0
        trip.totalKWhUsed = 2.0

        XCTAssertEqual(trip.efficiencyKWhPer100Km, 20.0, accuracy: 0.1)

        let sample1 = TelemetryPointModel(timestamp: Date(), speedKmH: 60.0, powerKW: 15.0, socPct: 89.0, batteryTempC: 25.0)
        let sample2 = TelemetryPointModel(timestamp: Date().addingTimeInterval(10), speedKmH: 80.0, powerKW: 22.0, socPct: 88.5, batteryTempC: 26.0)

        trip.samples.append(contentsOf: [sample1, sample2])
        XCTAssertEqual(trip.samples.count, 2)
        XCTAssertEqual(trip.samples[0].speedKmH, 60.0)
        XCTAssertEqual(trip.samples[1].powerKW, 22.0)
    }

    func testToggleDemoModeOffClearsTelemetry() {
        let manager = VehicleDataManager()
        XCTAssertTrue(manager.isDemoMode)

        manager.toggleDemoMode(false)
        XCTAssertFalse(manager.isDemoMode)
        XCTAssertEqual(manager.latestTelemetry.speedKmH, 0.0)
        XCTAssertEqual(manager.latestTelemetry.powerKW, 0.0)
        XCTAssertEqual(manager.latestTelemetry.stateOfChargePct, 0.0)
    }

    func testAutoTripStartAndStop() {
        let tracker = TripTrackingManager()
        tracker.isAutoTripEnabled = true
        tracker.autoStopDelaySeconds = 2

        XCTAssertFalse(tracker.isRecordingTrip)

        // Stationary update below threshold should not start trip
        var snap = TelemetrySnapshot()
        snap.speedKmH = 0.0
        tracker.processTelemetrySnapshot(snap)
        XCTAssertFalse(tracker.isRecordingTrip)

        // Speed >= 5 km/h triggers auto-start
        snap.speedKmH = 25.0
        tracker.processTelemetrySnapshot(snap)
        XCTAssertTrue(tracker.isRecordingTrip)
        XCTAssertNotNil(tracker.currentTrip)

        // Vehicle stops
        snap.speedKmH = 0.0
        tracker.processTelemetrySnapshot(snap)
        XCTAssertTrue(tracker.isRecordingTrip)

        // Wait past delay threshold (2 seconds)
        Thread.sleep(forTimeInterval: 2.1)
        tracker.processTelemetrySnapshot(snap)

        // Auto-stop triggers
        XCTAssertFalse(tracker.isRecordingTrip)
        XCTAssertNil(tracker.currentTrip)
    }
}
