import XCTest
@testable import VoltLinkEngine

@MainActor
final class TripDetailTests: XCTestCase {
    @MainActor
    func testDisplaySamplingBoundsLongTripsAndPreservesEndpointsWithoutChangingStoredSamples() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = TripModel(startTime: start)
        trip.samples = (0..<10_000).map {
            TelemetryPointModel(timestamp: start.addingTimeInterval(Double($0)), speedKmH: Double($0 % 100))
        }
        let samples = trip.samplePoints
        let display = TripDetailView.displaySamples(samples, limit: 500)

        XCTAssertEqual(display.count, 500)
        XCTAssertTrue(display.first === samples.first)
        XCTAssertTrue(display.last === samples.last)
        XCTAssertEqual(Set(display.map(\.persistentModelID)).count, 500)
        XCTAssertTrue(zip(display, display.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp })
        XCTAssertEqual(trip.samplePoints.count, 10_000)
        XCTAssertTrue(TripDetailView.displaySamples([], limit: 500).isEmpty)
        XCTAssertEqual(TripDetailView.displaySamples(Array(samples.prefix(2)), limit: 500).count, 2)
        XCTAssertEqual(TripDetailView.displaySamples(samples, limit: 1).count, 1)
        XCTAssertTrue(TripDetailView.displaySamples(samples, limit: 0).isEmpty)
    }

    /// A lone peak that uniform spacing steps over must survive extrema sampling.
    @MainActor
    func testExtremaSamplingKeepsPeaksThatUniformSpacingDrops() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = TripModel(startTime: start)
        trip.samples = (0..<10_000).map {
            TelemetryPointModel(timestamp: start.addingTimeInterval(Double($0)), speedKmH: $0 == 5_001 ? 250.0 : Double($0 % 100))
        }
        let samples = trip.samplePoints

        XCTAssertFalse(TripDetailView.displaySamples(samples, limit: 500).contains { $0.speedKmH == 250.0 })
        let peaks = TripDetailView.displaySamples(samples, limit: 500) { $0.speedKmH }
        XCTAssertEqual(peaks.count, 500)
        XCTAssertTrue(peaks.contains { $0.speedKmH == 250.0 })
        XCTAssertEqual(Set(peaks.map(\.persistentModelID)).count, 500)
        XCTAssertTrue(zip(peaks, peaks.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp })
        XCTAssertTrue(peaks.first === samples.first)
        XCTAssertTrue(peaks.last === samples.last)
        XCTAssertEqual(TripDetailView.displaySamples(samples, limit: 3) { $0.speedKmH }.count, 3)
    }

    func testComputedAverageSpeedAndAveragePower() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = TripModel(startTime: start, distanceKm: 50.0)
        trip.endTime = start.addingTimeInterval(3600)  // 1 hour duration
        trip.totalKWhUsed = 10.0

        // When samples are empty, falls back to distance / time or totalKWhUsed / time
        XCTAssertEqual(trip.computedAverageSpeedKmH, 50.0, accuracy: 0.01)
        XCTAssertEqual(trip.averagePowerKW, 10.0, accuracy: 0.01)

        // Add samples
        trip.samples = [
            TelemetryPointModel(timestamp: start, speedKmH: 40.0, powerKW: 12.0),
            TelemetryPointModel(timestamp: start.addingTimeInterval(10), speedKmH: 60.0, powerKW: 18.0),
            TelemetryPointModel(timestamp: start.addingTimeInterval(20), speedKmH: 80.0, powerKW: 30.0),
        ]

        // Average speed should be (40 + 60 + 80) / 3 = 60 km/h
        XCTAssertEqual(trip.computedAverageSpeedKmH, 60.0, accuracy: 0.01)
        // Average power should be (12 + 18 + 30) / 3 = 20 kW
        XCTAssertEqual(trip.averagePowerKW, 20.0, accuracy: 0.01)
    }
}
