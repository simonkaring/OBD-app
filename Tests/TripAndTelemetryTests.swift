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

    /// Locks in the fix for the hardcoded-0.5s trip energy bug: the first recorded sample has
    /// no prior timestamp to measure an interval against and must not accumulate any energy,
    /// and a subsequent sample must integrate over the real (small) elapsed gap rather than an
    /// assumed fixed 0.5s — which would have produced a much larger, gap-independent total.
    func testTripEnergyAccumulatesUsingMeasuredIntervalNotFixed05s() {
        let tracker = TripTrackingManager()
        tracker.startTrip(startSoc: 90.0)

        var telemetry = TelemetrySnapshot()
        telemetry.powerKW = 36.0 // chosen so 1 second of draw = 0.01 kWh, easy to sanity-check
        telemetry.speedKmH = 50.0

        tracker.recordSnapshot(telemetry)
        XCTAssertEqual(tracker.currentTrip?.totalKWhUsed, 0.0,
                        "first sample must not assume a fixed 0.5s interval")

        Thread.sleep(forTimeInterval: 0.2)
        tracker.recordSnapshot(telemetry)
        guard let accumulated = tracker.currentTrip?.totalKWhUsed else {
            return XCTFail("Expected an active trip with a recorded sample")
        }

        XCTAssertGreaterThan(accumulated, 0.0)
        // Expected ~36kW * ~0.2s/3600h ≈ 0.002 kWh. The old fixed-0.5s bug would have added
        // ~0.005 kWh on *every* call (including the first) regardless of real elapsed time;
        // bound this well below that to catch a regression back to the fixed interval.
        XCTAssertLessThan(accumulated, 0.01)
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

    func testEQAFullBatteryCaptureDoesNotInventChargingPower() throws {
        // 2026-09-06, 13:24:12-13:25:03 UTC: dashboard 100%, AC cable connected.
        // All 125 replies per DID were identical. Neither DID measures charging power.
        let profile = MercedesEQA250Profile()
        let voltage = try XCTUnwrap(profile.parseResponse(
            command: "22010A",
            rawResponse: "18 DA F1 59 05 62 01 0A 0D 77 \r\r>"
        ))
        let captureUpdates = profile.parseResponses(
            command: "220210",
            rawResponse: "18 DA F1 59 10 0B 62 02 10 04 00 00 \r18 DA F1 59 21 40 D0 00 00 00 AA AA \r\r>"
        )
        XCTAssertTrue(captureUpdates.isEmpty, "A full-charge match does not validate the SOC formula")
        let manager = VehicleDataManager()
        let recorder = ChargingTrackingManager()
        let start = Date.now
        for index in 0..<125 {
            // Approximate cadence; the export timestamps have whole-second precision.
            let timestamp = start.addingTimeInterval(Double(index) * 51 / 124)
            manager.applyUpdate(voltage, timestamp: timestamp)
            for update in captureUpdates {
                manager.applyUpdate(update, timestamp: timestamp)
            }
            recorder.processTelemetrySnapshot(manager.latestTelemetry)
        }

        XCTAssertEqual(manager.latestTelemetry.voltageV, 344.7, accuracy: 0.01)
        XCTAssertNil(manager.latestTelemetry.socUpdatedAt)
        XCTAssertFalse(manager.liveMetrics.contains(.soc))
        XCTAssertTrue(manager.liveMetrics.contains(.packVoltage))
        XCTAssertFalse(manager.hasChargePower, "Unmeasured power must not become a measured zero")
        XCTAssertNil(manager.latestTelemetry.chargePowerSource)
        XCTAssertFalse(manager.latestTelemetry.isCharging)
        XCTAssertFalse(manager.chargingSession.isCharging)
        XCTAssertFalse(recorder.isRecordingSession)
    }

    func testSustainedHighResolutionSOCEstimatesChargingPower() {
        let manager = VehicleDataManager()
        let startedAt = Date.now
        manager.applyUpdate(.soc(62.000), timestamp: startedAt)
        manager.applyUpdate(.soc(62.046), timestamp: startedAt.addingTimeInterval(10))
        manager.applyUpdate(.soc(62.091), timestamp: startedAt.addingTimeInterval(20))
        manager.applyUpdate(.soc(62.137), timestamp: startedAt.addingTimeInterval(30))

        XCTAssertTrue(manager.latestTelemetry.isCharging)
        XCTAssertEqual(manager.latestTelemetry.chargePowerKW, 10.93, accuracy: 0.2)
        XCTAssertEqual(manager.latestTelemetry.chargePowerSource, .socEstimate)
        XCTAssertTrue(manager.hasChargePower)
        XCTAssertFalse(manager.liveMetrics.contains(.power))
        XCTAssertEqual(manager.latestTelemetry.powerKW, 0, "An SOC estimate is not measured pack power")
    }

    func testSelectedVehicleCapacityDrivesChargingEstimate() {
        let manager = VehicleDataManager()
        let ioniq = VehicleCatalog.allModels.first {
            $0.profileID == .hkmcIoniq5 && $0.batteryCapacityKWh > 70
        }!
        manager.selectVehicle(ioniq)

        let startedAt = Date.now
        manager.applyUpdate(.soc(62.000), timestamp: startedAt)
        manager.applyUpdate(.soc(62.046), timestamp: startedAt.addingTimeInterval(10))
        manager.applyUpdate(.soc(62.091), timestamp: startedAt.addingTimeInterval(20))
        manager.applyUpdate(.soc(62.137), timestamp: startedAt.addingTimeInterval(30))

        XCTAssertTrue(manager.vehicleName.localizedCaseInsensitiveContains("Ioniq 5"))
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
        XCTAssertEqual(manager.latestTelemetry.chargePowerSource, .measured)
    }

    func testSOCEstimateEndsOnPlateauAndRecordingStops() {
        let manager = VehicleDataManager()
        let tracker = ChargingTrackingManager()
        let start = Date.now
        for seconds in stride(from: 0, through: 30, by: 10) {
            manager.applyUpdate(.soc(50 + Double(seconds) * 0.004), timestamp: start.addingTimeInterval(Double(seconds)))
        }
        tracker.processTelemetrySnapshot(manager.latestTelemetry)
        XCTAssertTrue(tracker.isRecordingSession)

        for seconds in stride(from: 40, through: 150, by: 10) {
            manager.applyUpdate(.soc(50.12), timestamp: start.addingTimeInterval(Double(seconds)))
            tracker.processTelemetrySnapshot(manager.latestTelemetry)
        }
        XCTAssertFalse(manager.latestTelemetry.isCharging)
        XCTAssertEqual(manager.latestTelemetry.chargePowerKW, 0)
        XCTAssertEqual(manager.latestTelemetry.powerKW, 0)
        XCTAssertFalse(manager.hasChargePower)
        XCTAssertFalse(tracker.isRecordingSession)
    }

    func testVoltageUpdatesDoNotKeepMissingSOCEstimateAlive() {
        let manager = VehicleDataManager()
        let start = Date.now
        for seconds in stride(from: 0, through: 30, by: 10) {
            manager.applyUpdate(.soc(50 + Double(seconds) * 0.004), timestamp: start.addingTimeInterval(Double(seconds)))
        }
        XCTAssertTrue(manager.hasChargePower)
        manager.applyUpdate(.packVoltage(380), timestamp: start.addingTimeInterval(46))
        XCTAssertFalse(manager.hasChargePower)
        XCTAssertFalse(manager.latestTelemetry.isCharging)
        XCTAssertFalse(manager.chargingSession.isCharging)

        manager.applyUpdate(.soc(51), timestamp: start.addingTimeInterval(50))
        XCTAssertFalse(manager.hasChargePower, "Recovery requires a new continuous SOC history")
    }

    func testRisingSOCWhileMovingDoesNotEstimateCharging() {
        let manager = VehicleDataManager()
        let start = Date.now
        manager.applyUpdate(.speed(40), timestamp: start)
        for seconds in stride(from: 0, through: 60, by: 10) {
            manager.applyUpdate(.soc(50 + Double(seconds) * 0.004), timestamp: start.addingTimeInterval(Double(seconds)))
        }
        XCTAssertFalse(manager.latestTelemetry.isCharging)
        XCTAssertFalse(manager.hasChargePower)
    }

    func testStoppingPollingClearsEstimateAndHistory() {
        let manager = VehicleDataManager()
        let start = Date.now
        for seconds in stride(from: 0, through: 30, by: 10) {
            manager.applyUpdate(.soc(50 + Double(seconds) * 0.004), timestamp: start.addingTimeInterval(Double(seconds)))
        }
        XCTAssertTrue(manager.hasChargePower)
        manager.stopPolling()
        XCTAssertFalse(manager.hasChargePower)
        XCTAssertFalse(manager.latestTelemetry.isCharging)
        XCTAssertFalse(manager.chargingSession.isCharging)
        XCTAssertEqual(manager.chargingSession.currentPowerKW, 0)
        manager.applyUpdate(.soc(50.16), timestamp: start.addingTimeInterval(40))
        XCTAssertFalse(manager.hasChargePower)
    }

    func testLowPowerACChargingCanBeEstimated() {
        let manager = VehicleDataManager()
        let start = Date.now
        for seconds in stride(from: 0, through: 90, by: 10) {
            let soc = 50 + (0.8 / 66.5 * 100 * Double(seconds) / 3600)
            manager.applyUpdate(.soc(soc), timestamp: start.addingTimeInterval(Double(seconds)))
        }
        XCTAssertEqual(manager.latestTelemetry.chargePowerKW, 0.8, accuracy: 0.01)
        XCTAssertEqual(manager.latestTelemetry.chargePowerSource, .socEstimate)
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

    func testIsPlausibleClampsAdditionalMetricRanges() {
        XCTAssertFalse(VehicleDataManager.isPlausible(.speed(500.0)))
        XCTAssertTrue(VehicleDataManager.isPlausible(.speed(120.0)))
        XCTAssertFalse(VehicleDataManager.isPlausible(.aux12V(40.0)))
        XCTAssertTrue(VehicleDataManager.isPlausible(.aux12V(12.6)))
        XCTAssertFalse(VehicleDataManager.isPlausible(.motorStats(rpm: 50_000, torque: 0)))
        XCTAssertTrue(VehicleDataManager.isPlausible(.motorStats(rpm: 3_000, torque: 100)))
        XCTAssertFalse(VehicleDataManager.isPlausible(.coolantTemp(300.0)))
        XCTAssertTrue(VehicleDataManager.isPlausible(.coolantTemp(90.0)))
        XCTAssertFalse(VehicleDataManager.isPlausible(.chargingStats(kwRate: 1_000.0, acOrDc: "DC")))
        XCTAssertTrue(VehicleDataManager.isPlausible(.chargingStats(kwRate: nil, acOrDc: "AC")))
    }

    /// Locks in the fix for the fixed-dt kWh integration bug: the very first `update` call
    /// establishes the baseline timestamp only and must not assume any elapsed interval, and
    /// a longer real gap between calls must integrate proportionally more energy than a
    /// shorter one — which a hardcoded interval could never reproduce.
    func testChargingSessionTrackerIntegratesRealMeasuredInterval() {
        let tracker = ChargingSessionTracker()

        let started = tracker.update(soc: 50, packVoltage: 400, packCurrent: -25, powerKW: nil,
                                      vehicleBatteryCapacityKWh: 66.5, isStationary: true)
        XCTAssertEqual(started.totalEnergyKWh, 0.0, "first sample must not assume a fixed interval")

        Thread.sleep(forTimeInterval: 0.1)
        let afterShortGap = tracker.update(soc: 50, packVoltage: 400, packCurrent: -25, powerKW: nil,
                                            vehicleBatteryCapacityKWh: 66.5, isStationary: true)
        XCTAssertGreaterThan(afterShortGap.totalEnergyKWh, 0.0)

        Thread.sleep(forTimeInterval: 0.3)
        let afterLongGap = tracker.update(soc: 50, packVoltage: 400, packCurrent: -25, powerKW: nil,
                                           vehicleBatteryCapacityKWh: 66.5, isStationary: true)
        let longGapIncrement = afterLongGap.totalEnergyKWh - afterShortGap.totalEnergyKWh

        // The ~0.3s gap should integrate meaningfully more energy than the ~0.1s gap did;
        // a fixed-interval implementation would instead add the same amount every call.
        XCTAssertGreaterThan(longGapIncrement, afterShortGap.totalEnergyKWh * 2)
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
