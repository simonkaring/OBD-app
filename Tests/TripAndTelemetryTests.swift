import XCTest
import Combine
@testable import VoltLinkEngine

final class TripAndTelemetryTests: XCTestCase {

    func testSimulationStepPublishesOneTelemetrySnapshot() {
        let simulation = MockDrivingSimulation()
        var publishedSnapshots = 0
        let cancellable = simulation.$telemetry.dropFirst().sink { _ in
            publishedSnapshots += 1
        }

        simulation.stepSimulation()

        XCTAssertEqual(publishedSnapshots, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testSimulationStepsAdvanceTelemetryTimestamp() {
        let simulation = MockDrivingSimulation()
        let initialTimestamp = simulation.telemetry.timestamp

        simulation.stepSimulation()

        XCTAssertGreaterThan(simulation.telemetry.timestamp, initialTimestamp)
    }

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

    func testRouteSamplesIgnoreInvalidCoordinatesAndRepeatedLocations() {
        let trip = TripModel()
        let later = Date.now
        let earlier = later.addingTimeInterval(-10)
        trip.samples = [
            TelemetryPointModel(timestamp: later, latitude: 55.6761, longitude: 12.5683),
            TelemetryPointModel(timestamp: earlier, latitude: 55.6759, longitude: 12.5681),
            TelemetryPointModel(timestamp: later.addingTimeInterval(1), latitude: 55.6761, longitude: 12.5683),
            TelemetryPointModel(timestamp: later.addingTimeInterval(2), latitude: 0, longitude: 0),
            TelemetryPointModel(timestamp: later.addingTimeInterval(3), latitude: 91, longitude: 12.5683)
        ]

        XCTAssertEqual(trip.routeSamples.count, 2)
        XCTAssertEqual(trip.routeSamples.first?.timestamp, earlier)
        XCTAssertEqual(trip.routeSamples.last?.timestamp, later)
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

    func testSOCDoesNotInventChargingPower() {
        let manager = VehicleDataManager()
        manager.applyUpdate(.speed(0.0))
        manager.applyUpdate(.soc(36.0))
        manager.applyUpdate(.soc(36.2))

        XCTAssertFalse(manager.latestTelemetry.isCharging)
        XCTAssertEqual(manager.latestTelemetry.chargePowerKW, 0.0)
        XCTAssertNotNil(manager.latestTelemetry.socUpdatedAt)
    }

    func testSustainedHighResolutionSOCEstimatesChargingPower() {
        let manager = VehicleDataManager()
        let startedAt = Date.now
        manager.applyUpdate(.soc(62.000), timestamp: startedAt)
        manager.applyUpdate(.soc(62.137), timestamp: startedAt.addingTimeInterval(30))

        XCTAssertTrue(manager.latestTelemetry.isCharging)
        XCTAssertEqual(manager.latestTelemetry.chargePowerKW, 10.93, accuracy: 0.2)
    }

    func testSelectedVehicleCapacityDrivesChargingEstimate() {
        let manager = VehicleDataManager()
        let ioniq = VehicleCatalog.allModels.first { $0.modelName.localizedCaseInsensitiveContains("Ioniq 5") }!
        manager.selectVehicle(ioniq)

        let startedAt = Date.now
        manager.applyUpdate(.soc(62.000), timestamp: startedAt)
        manager.applyUpdate(.soc(62.137), timestamp: startedAt.addingTimeInterval(30))

        XCTAssertTrue(manager.vehicleName.contains("Ioniq 5"))
        XCTAssertGreaterThan(manager.usableBatteryCapacityKWh, 70.0)
        XCTAssertGreaterThan(manager.latestTelemetry.chargePowerKW, 0.0)
        XCTAssertEqual(manager.selectedProfileID, .hkmcIoniq5)
    }

    func testDirectPackPowerWinsOverSOCEstimate() {
        let manager = VehicleDataManager()
        let startedAt = Date.now
        manager.applyUpdate(.soc(50.0), timestamp: startedAt)
        manager.applyUpdate(.power(voltage: 400, current: -25, powerKW: -10), timestamp: startedAt.addingTimeInterval(30))
        manager.applyUpdate(.soc(50.2), timestamp: startedAt.addingTimeInterval(31))

        XCTAssertEqual(manager.latestTelemetry.chargePowerKW, 10.0, accuracy: 0.01)
    }

    func testStandalonePackCurrentUsesMeasuredVoltage() {
        let manager = VehicleDataManager()
        manager.applyUpdate(.packVoltage(339.0))
        manager.applyUpdate(.packCurrent(-10.0))

        XCTAssertEqual(manager.latestTelemetry.voltageV, 339.0, accuracy: 0.01)
        XCTAssertEqual(manager.latestTelemetry.currentA, -10.0, accuracy: 0.01)
        XCTAssertEqual(manager.latestTelemetry.powerKW, -3.39, accuracy: 0.01)
    }

    func testDemoModeFlagControllingDemoTrips() {
        let manager = VehicleDataManager()
        XCTAssertFalse(manager.isDemoMode)
        
        manager.toggleDemoMode(true)
        XCTAssertTrue(manager.isDemoMode)
        
        manager.toggleDemoMode(false)
        XCTAssertFalse(manager.isDemoMode)
    }

    func testChargingTrackingManagerSessionLifecycle() {
        let tracker = ChargingTrackingManager()
        XCTAssertFalse(tracker.isRecordingSession)
        XCTAssertNil(tracker.currentSession)

        var snap = TelemetrySnapshot()
        snap.speedKmH = 0.0
        snap.isCharging = true
        snap.chargePowerKW = 50.0
        snap.stateOfChargePct = 20.0

        // Step 1: Start charging session
        tracker.processTelemetrySnapshot(snap)
        XCTAssertTrue(tracker.isRecordingSession)
        XCTAssertNotNil(tracker.currentSession)
        XCTAssertEqual(tracker.currentSession?.startSocPct, 20.0)
        XCTAssertEqual(tracker.currentSession?.peakPowerKW, 50.0)

        // Step 2: Intermediate charging update
        snap.chargePowerKW = 75.0
        snap.stateOfChargePct = 25.0
        tracker.processTelemetrySnapshot(snap)
        XCTAssertEqual(tracker.currentSession?.peakPowerKW, 75.0)
        XCTAssertEqual(tracker.currentSession?.endSocPct, 25.0)

        // Step 3: Stop charging. A single non-charging snapshot must NOT end the session —
        // hysteresis keeps one charge from fragmenting on a dropped poll.
        snap.isCharging = false
        snap.chargePowerKW = 0.0
        tracker.processTelemetrySnapshot(snap)
        XCTAssertTrue(tracker.isRecordingSession)

        for _ in 1..<ChargingTrackingManager.endSessionSnapshotThreshold {
            tracker.processTelemetrySnapshot(snap)
        }
        XCTAssertFalse(tracker.isRecordingSession)
        XCTAssertNil(tracker.currentSession)
    }

    /// A parked car drawing power (HVAC, preconditioning) signs pack current *positive*;
    /// only current flowing into the pack may open a charging session.
    func testDischargeWhileParkedDoesNotStartChargingSession() {
        let tracker = ChargingSessionTracker()
        let state = tracker.update(
            soc: 50.0,
            packVoltage: 400.0,
            packCurrent: 8.0,
            powerKW: nil,
            vehicleBatteryCapacityKWh: 66.5,
            isStationary: true
        )
        XCTAssertFalse(state.isCharging)
    }

    func testChargeDirectionCurrentWhileParkedStartsSession() {
        let tracker = ChargingSessionTracker()
        let state = tracker.update(
            soc: 50.0,
            packVoltage: 400.0,
            packCurrent: -25.0,
            powerKW: nil,
            vehicleBatteryCapacityKWh: 66.5,
            isStationary: true
        )
        XCTAssertTrue(state.isCharging)
        XCTAssertEqual(state.currentPowerKW, 10.0, accuracy: 0.01)
    }

    /// `sessionDuration` used to keep growing after a session ended because `startTime`
    /// was never cleared.
    func testSessionDurationStopsAtSessionEnd() {
        let tracker = ChargingSessionTracker()
        _ = tracker.update(soc: 50, packVoltage: 400, packCurrent: -25, powerKW: nil, vehicleBatteryCapacityKWh: 66.5, isStationary: true)
        let ended = tracker.update(soc: 50, packVoltage: 400, packCurrent: 0, powerKW: nil, vehicleBatteryCapacityKWh: 66.5, isStationary: true)
        XCTAssertFalse(ended.isCharging)
        XCTAssertEqual(ended.sessionDuration, 0)
    }

    /// Out-of-range decodes (a wrong community scaling factor) must be dropped, not
    /// published as garbage.
    func testImplausibleDecodesAreRejected() {
        XCTAssertFalse(VehicleDataManager.isPlausible(.soc(3_200.0)))
        XCTAssertFalse(VehicleDataManager.isPlausible(.batteryTemp(min: -300, max: -300, avg: -300)))
        XCTAssertFalse(VehicleDataManager.isPlausible(.packVoltage(.nan)))
        XCTAssertTrue(VehicleDataManager.isPlausible(.soc(58.9)))
        XCTAssertTrue(VehicleDataManager.isPlausible(.packCurrent(0.0)))

        let manager = VehicleDataManager()
        manager.applyUpdate(.soc(42.0))
        manager.applyUpdate(.soc(3_200.0))
        XCTAssertEqual(manager.latestTelemetry.stateOfChargePct, 42.0, accuracy: 0.01)
    }

    /// A genuine 0 A pack current is data, not a "no reading" sentinel.
    func testZeroPackCurrentReachesChargingTracker() {
        let manager = VehicleDataManager()
        manager.applyUpdate(.packVoltage(400.0))
        manager.applyUpdate(.packCurrent(0.0))

        XCTAssertTrue(manager.liveMetrics.contains(.packCurrent))
        XCTAssertEqual(manager.latestTelemetry.powerKW, 0.0, accuracy: 0.01)
        XCTAssertFalse(manager.chargingSession.isCharging)
    }
}
