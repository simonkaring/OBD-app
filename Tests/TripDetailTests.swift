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
}
