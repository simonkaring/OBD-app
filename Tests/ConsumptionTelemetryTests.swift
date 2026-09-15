import XCTest
@testable import VoltLinkEngine

final class ConsumptionTelemetryTests: XCTestCase {
    func testConsumptionAndRegenRequireFreshInputsAndDistinguishCharging() {
        let manager = VehicleDataManager()
        manager.selectProfile(.mercedesEQAOBDb)
        XCTAssertTrue(manager.supportedMetrics.isSuperset(of: [.instantEfficiency, .tripAverageConsumption, .regenPower, .vehicleRange]))
        let now = Date.now
        manager.applyUpdates([.speed(100), .packVoltage(400), .packCurrent(50)], timestamp: now)
        var snapshot = manager.latestTelemetry
        XCTAssertTrue(manager.liveMetrics.contains(.instantEfficiency))
        XCTAssertTrue(TelemetryMetric.instantEfficiency.isAvailable(in: snapshot, liveMetrics: manager.liveMetrics))
        XCTAssertEqual(TelemetryMetric.instantEfficiency.value(in: snapshot), 20)
        XCTAssertEqual(TelemetryMetric.regenPower.value(in: snapshot), 0)

        manager.applyUpdate(.packCurrent(-25), timestamp: now)
        snapshot = manager.latestTelemetry
        XCTAssertEqual(TelemetryMetric.instantEfficiency.value(in: snapshot), -10)
        XCTAssertEqual(TelemetryMetric.regenPower.value(in: snapshot), 10)
        XCTAssertFalse(snapshot.isCharging)

        manager.applyUpdate(.speed(3), timestamp: now)
        XCTAssertFalse(TelemetryMetric.instantEfficiency.isAvailable(in: manager.latestTelemetry, liveMetrics: manager.liveMetrics))
        manager.applyUpdates([.speed(0), .packCurrent(-25)], timestamp: now)
        XCTAssertTrue(manager.latestTelemetry.isCharging)
        XCTAssertEqual(TelemetryMetric.regenPower.value(in: manager.latestTelemetry), 0)

        XCTAssertFalse(TelemetryMetric.regenPower.isAvailable(in: snapshot, liveMetrics: manager.liveMetrics, at: now.addingTimeInterval(16)))
        manager.applyUpdate(.speed(100), timestamp: now.addingTimeInterval(16))
        manager.applyUpdate(.packCurrent(50), timestamp: now.addingTimeInterval(16))
        XCTAssertFalse(manager.latestTelemetry.hasFreshPower, "An old voltage must not make a new current reading look like fresh power")
        XCTAssertFalse(TelemetryMetric.instantEfficiency.isAvailable(in: manager.latestTelemetry, liveMetrics: manager.liveMetrics))
        manager.applyUpdate(.packVoltage(400), timestamp: now.addingTimeInterval(16))
        XCTAssertTrue(TelemetryMetric.instantEfficiency.isAvailable(in: manager.latestTelemetry, liveMetrics: manager.liveMetrics))

        let missingPower = TelemetryMetric.includingDerivedMetrics(manager.liveMetrics.subtracting([.power]))
        XCTAssertFalse(missingPower.contains(.instantEfficiency))
        XCTAssertFalse(missingPower.contains(.regenPower))
        manager.applyExternalSpeed(100, timestamp: now)
        manager.clearExternalSpeed()
        XCTAssertFalse(manager.liveMetrics.contains(.instantEfficiency))
        XCTAssertFalse(manager.liveMetrics.contains(.regenPower))
        manager.selectProfile(.genericOBD2)
        XCTAssertFalse(manager.supportedMetrics.contains(.instantEfficiency))
        XCTAssertFalse(manager.supportedMetrics.contains(.vehicleRange))
    }

    func testVehicleRangeDecodingAndAvailability() throws {
        let profile = MercedesEQAOBDbProfile()
        XCTAssertTrue(profile.pollingCommands.contains("226502"))
        let update = try XCTUnwrap(profile.parseResponse(command: "22 65 02", rawResponse: "7ED 07 62 65 02 00 00 01 40"))
        guard case .vehicleRange(let km) = update else { return XCTFail("Expected range") }
        XCTAssertEqual(km, 320)
        for raw in ["NO DATA", "7ED 03 7F 22 31", "7EC 07 62 65 02 00 00 01 40", "7ED 06 62 65 02 00 00 01", "7ED 07 62 65 02 FF FF FF FF", "7ED 07 62 65 04 00 00 01 40", "62 65 02 00 00 01 40"] {
            XCTAssertNil(profile.parseResponse(command: "226502", rawResponse: raw), raw)
        }
        XCTAssertNotNil(profile.parseResponse(command: "226502", rawResponse: "7ED 07 62 65 02 00 00 00 00"))
        XCTAssertFalse(VehicleDataManager.isPlausible(.vehicleRange(.nan)))
        XCTAssertFalse(VehicleDataManager.isPlausible(.vehicleRange(-1)))
        let manager = VehicleDataManager()
        manager.applyUpdate(update)
        XCTAssertEqual(manager.latestTelemetry.vehicleRangeKm, 320)
        XCTAssertTrue(TelemetryMetric.vehicleRange.isAvailable(in: manager.latestTelemetry, liveMetrics: manager.liveMetrics))
        XCTAssertFalse(TelemetryMetric.vehicleRange.isAvailable(in: manager.latestTelemetry, liveMetrics: manager.liveMetrics, at: .now.addingTimeInterval(16)))
        XCTAssertFalse(TelemetryMetric.vehicleRange.isAvailable(in: TelemetrySnapshot(), liveMetrics: [.vehicleRange]))
    }

    func testTripAverageSubtractsRegenExcludesChargingAndResets() throws {
        let tracker = TripTrackingManager()
        tracker.setDemoMode(true, endSoc: 80)
        tracker.startTrip()
        defer { tracker.stopTrip() }
        let start = Date.now
        var snapshot = TelemetrySnapshot()
        snapshot.speedKmH = 60
        snapshot.powerKW = 36
        tracker.recordSnapshot(snapshot, at: start)
        XCTAssertNil(tracker.averageConsumption)
        tracker.recordSnapshot(snapshot, at: start.addingTimeInterval(60))
        XCTAssertEqual(try XCTUnwrap(tracker.averageConsumption), 60, accuracy: 0.001)

        snapshot.timestamp = start.addingTimeInterval(120)
        snapshot.speedUpdatedAt = snapshot.timestamp
        snapshot.powerKW = -18
        tracker.recordSnapshot(snapshot, at: snapshot.timestamp)
        let trip = try XCTUnwrap(tracker.currentTrip)
        XCTAssertEqual(trip.totalKWhUsed, 0.6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(trip.totalKWhRecovered), 0.3, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(tracker.averageConsumption), 15, accuracy: 0.001)

        // The wheel-speed reply can report a stop before pack current catches up.
        snapshot.speedKmH = 0
        tracker.recordSnapshot(snapshot, at: start.addingTimeInterval(121))
        XCTAssertEqual(try XCTUnwrap(tracker.averageConsumption), 15, accuracy: 0.001)
        snapshot.isCharging = true
        snapshot.speedKmH = 0
        snapshot.powerKW = -100
        tracker.recordSnapshot(snapshot, at: start.addingTimeInterval(180))
        XCTAssertEqual(try XCTUnwrap(tracker.averageConsumption), 15, accuracy: 0.001)
        let displayed = tracker.telemetryForDisplay(snapshot)
        XCTAssertEqual(TelemetryMetric.tripAverageConsumption.value(in: displayed), 15, accuracy: 0.001)
        XCTAssertTrue(TelemetryMetric.tripAverageConsumption.isAvailable(in: displayed, liveMetrics: []))

        snapshot.isCharging = false
        snapshot.powerKW = 36
        tracker.recordSnapshot(snapshot, at: start.addingTimeInterval(181), hasPowerData: false)
        XCTAssertNil(tracker.averageConsumption, "Missing energy must not produce a falsely low average")
        tracker.recordSnapshot(snapshot, at: start.addingTimeInterval(182))
        XCTAssertNil(tracker.averageConsumption)
        tracker.stopTrip()
        XCTAssertNil(tracker.averageConsumption)
        tracker.startTrip()
        XCTAssertNil(tracker.averageConsumption)
        XCTAssertEqual(tracker.currentTrip?.totalKWhRecovered, 0)

        trip.totalKWhRecovered = nil // Legacy recordings retain their original average.
        XCTAssertEqual(trip.efficiencyKWhPer100Km, trip.totalKWhUsed / trip.distanceKm * 100)
    }

    func testDemoAndOlderSnapshotCompatibility() throws {
        let simulation = MockDrivingSimulation()
        simulation.scenario = .highwayCruising
        simulation.stepSimulation()
        let snapshot = simulation.telemetry
        for metric: TelemetryMetric in [.instantEfficiency, .regenPower, .vehicleRange] {
            XCTAssertTrue(metric.isAvailable(in: snapshot, liveMetrics: [], isDemoMode: true))
        }
        XCTAssertGreaterThan(try XCTUnwrap(snapshot.vehicleRangeKm), 0)
        simulation.scenario = .dcFastCharging
        simulation.stepSimulation()
        XCTAssertEqual(TelemetryMetric.regenPower.value(in: simulation.telemetry), 0)
        XCTAssertFalse(TelemetryMetric.instantEfficiency.isAvailable(in: simulation.telemetry, liveMetrics: [], isDemoMode: true))

        let data = try JSONEncoder().encode(TelemetrySnapshot())
        // Optional additions are omitted when nil, matching the old snapshot format.
        let decoded = try JSONDecoder().decode(TelemetrySnapshot.self, from: data)
        XCTAssertNil(decoded.vehicleRangeKm)
        XCTAssertNil(decoded.tripAverageConsumption)
        XCTAssertNil(decoded.powerUpdatedAt)
    }

    func testAutoTripWaitsForEVPowerButGenericTripsStillRecord() {
        let tracker = TripTrackingManager()
        let originalAuto = tracker.isAutoTripEnabled
        tracker.isAutoTripEnabled = true
        defer {
            tracker.stopTrip()
            tracker.isAutoTripEnabled = originalAuto
        }
        tracker.setDemoMode(true, endSoc: 80)
        var snapshot = TelemetrySnapshot()
        snapshot.speedKmH = 30
        tracker.processTelemetrySnapshot(snapshot, hasPowerData: false, requiresPowerForAutoStart: true)
        XCTAssertFalse(tracker.isRecordingTrip)
        tracker.processTelemetrySnapshot(snapshot, hasPowerData: true, requiresPowerForAutoStart: true)
        XCTAssertTrue(tracker.isRecordingTrip)
        tracker.stopTrip()
        tracker.processTelemetrySnapshot(snapshot, hasPowerData: false, requiresPowerForAutoStart: false)
        XCTAssertTrue(tracker.isRecordingTrip)
        XCTAssertNil(tracker.averageConsumption)
    }
}
