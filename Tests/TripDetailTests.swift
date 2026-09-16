import XCTest
@testable import VoltLinkEngine

final class TripDetailTests: XCTestCase {
    @MainActor
    func testDisplaySamplingBoundsLongTripsAndPreservesEndpointsWithoutChangingStoredSamples() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = TripModel(startTime: start)
        trip.samples = (0..<10_000).map {
            TelemetryPointModel(timestamp: start.addingTimeInterval(Double($0)), speedKmH: Double($0 % 100))
        }
        let samples = trip.samples
        let display = TripDetailView.displaySamples(samples, limit: 500)

        XCTAssertEqual(display.count, 500)
        XCTAssertTrue(display.first === samples.first)
        XCTAssertTrue(display.last === samples.last)
        XCTAssertEqual(Set(display.map(\.persistentModelID)).count, 500)
        XCTAssertTrue(zip(display, display.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp })
        XCTAssertEqual(trip.samples.count, 10_000)
        XCTAssertTrue(TripDetailView.displaySamples([], limit: 500).isEmpty)
        XCTAssertEqual(TripDetailView.displaySamples(Array(samples.prefix(2)), limit: 500).count, 2)
        XCTAssertEqual(TripDetailView.displaySamples(samples, limit: 1).count, 1)
        XCTAssertTrue(TripDetailView.displaySamples(samples, limit: 0).isEmpty)
    }

    func testComputedAverageSpeedAndAveragePower() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = TripModel(startTime: start, distanceKm: 50.0)
        trip.endTime = start.addingTimeInterval(3600) // 1 hour duration
        trip.totalKWhUsed = 10.0

        // When samples are empty, falls back to distance / time or totalKWhUsed / time
        XCTAssertEqual(trip.computedAverageSpeedKmH, 50.0, accuracy: 0.01)
        XCTAssertEqual(trip.averagePowerKW, 10.0, accuracy: 0.01)

        // Add samples
        trip.samples = [
            TelemetryPointModel(timestamp: start, speedKmH: 40.0, powerKW: 12.0),
            TelemetryPointModel(timestamp: start.addingTimeInterval(10), speedKmH: 60.0, powerKW: 18.0),
            TelemetryPointModel(timestamp: start.addingTimeInterval(20), speedKmH: 80.0, powerKW: 30.0)
        ]

        // Average speed should be (40 + 60 + 80) / 3 = 60 km/h
        XCTAssertEqual(trip.computedAverageSpeedKmH, 60.0, accuracy: 0.01)
        // Average power should be (12 + 18 + 30) / 3 = 20 kW
        XCTAssertEqual(trip.averagePowerKW, 20.0, accuracy: 0.01)
    }
}
