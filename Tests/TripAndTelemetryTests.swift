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
        XCTAssertFalse(manager.isDemoMode)

        manager.toggleDemoMode(true)
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

    func testMergeWithinWindowCombinesTrips() {
        let tracker = TripTrackingManager()
        let older = TripModel(startTime: Date().addingTimeInterval(-3600), distanceKm: 10.0, startSocPct: 90.0)
        older.endTime = Date().addingTimeInterval(-3600 + 600)
        older.endSocPct = 85.0
        older.totalKWhUsed = 2.0
        older.maxPowerKW = 30.0
        older.maxRegenKW = -5.0

        let newer = TripModel(startTime: older.endTime!.addingTimeInterval(10 * 60), distanceKm: 5.0, startSocPct: 85.0)
        newer.endTime = newer.startTime.addingTimeInterval(300)
        newer.endSocPct = 82.0
        newer.totalKWhUsed = 1.0
        newer.maxPowerKW = 40.0
        newer.maxRegenKW = -8.0

        XCTAssertTrue(tracker.canMerge(newer, into: older))
        tracker.merge(newer, into: older)

        XCTAssertEqual(older.distanceKm, 15.0, accuracy: 0.01)
        XCTAssertEqual(older.totalKWhUsed, 3.0, accuracy: 0.01)
        XCTAssertEqual(older.maxPowerKW, 40.0, accuracy: 0.01)
        XCTAssertEqual(older.maxRegenKW, -8.0, accuracy: 0.01)
        XCTAssertEqual(older.endSocPct, 82.0, accuracy: 0.01)
        XCTAssertEqual(older.endTime, newer.endTime)
    }

    func testMergeOutsideWindowIsRejected() {
        let tracker = TripTrackingManager()
        let older = TripModel(startTime: Date().addingTimeInterval(-7200), distanceKm: 10.0, startSocPct: 90.0)
        older.endTime = Date().addingTimeInterval(-7200 + 600)

        let newer = TripModel(startTime: older.endTime!.addingTimeInterval(31 * 60), distanceKm: 5.0, startSocPct: 85.0)
        newer.endTime = newer.startTime.addingTimeInterval(300)

        XCTAssertFalse(tracker.canMerge(newer, into: older))
        tracker.merge(newer, into: older)
        XCTAssertEqual(older.distanceKm, 10.0, accuracy: 0.01)
    }

    func testChargingDetectedFromNegativeCurrentWhileParked() {
        let manager = VehicleDataManager()
        manager.applyUpdate(.speed(0.0))
        manager.applyUpdate(.power(voltage: 380.0, current: -50.0, powerKW: -19.0))

        XCTAssertTrue(manager.latestTelemetry.isCharging)
        XCTAssertEqual(manager.latestTelemetry.chargePowerKW, 19.0, accuracy: 0.01)
    }

    func testNegativeCurrentWhileMovingIsRegenNotCharging() {
        let manager = VehicleDataManager()
        manager.applyUpdate(.speed(50.0))
        manager.applyUpdate(.power(voltage: 380.0, current: -50.0, powerKW: -19.0))

        XCTAssertFalse(manager.latestTelemetry.isCharging)
        XCTAssertEqual(manager.latestTelemetry.chargePowerKW, 0.0, accuracy: 0.01)
    }

    func testChargingCalculatedFromSOCSlopeWhileParked() {
        let manager = VehicleDataManager()
        manager.applyUpdate(.speed(0.0))

        // Initial sample
        manager.applyUpdate(.soc(36.0))

        // Wait small interval then report SOC gain
        Thread.sleep(forTimeInterval: 5.1)
        manager.applyUpdate(.soc(36.2))

        XCTAssertTrue(manager.latestTelemetry.isCharging)
        XCTAssertGreaterThan(manager.latestTelemetry.chargePowerKW, 0.5)

        // When vehicle moves, charging resets
        manager.applyUpdate(.speed(20.0))
        XCTAssertFalse(manager.latestTelemetry.isCharging)
        XCTAssertEqual(manager.latestTelemetry.chargePowerKW, 0.0)
    }

    func testDemoModeFlagControllingDemoTrips() {
        let manager = VehicleDataManager()
        XCTAssertFalse(manager.isDemoMode)
        
        manager.toggleDemoMode(true)
        XCTAssertTrue(manager.isDemoMode)
        
        manager.toggleDemoMode(false)
        XCTAssertFalse(manager.isDemoMode)
    }
}
