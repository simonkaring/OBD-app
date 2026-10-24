import XCTest

@testable import VoltLinkEngine

@MainActor
final class TripHistoryInsightsTests: XCTestCase {
    private func trip(start: Date, distanceKm: Double = 10, used: Double = 2, recovered: Double? = 0.2, completed: Bool = true) -> TripModel {
        let model = TripModel(startTime: start, distanceKm: distanceKm, startSocPct: 80)
        model.endTime = completed ? start.addingTimeInterval(600) : nil
        model.totalKWhUsed = used
        model.totalKWhRecovered = recovered
        return model
    }

    func testSummarizeUsesNetEnergyAndWeightedEfficiency() {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let trips = [
            trip(start: since, distanceKm: 10, used: 2, recovered: 0.2),
            trip(start: since.addingTimeInterval(3_600), distanceKm: 30, used: 6, recovered: 0.5),
        ]

        let insights = TripHistoryInsights.summarize(trips: trips, since: since, pricePerKWh: 0.4)

        XCTAssertEqual(insights.tripCount, 2)
        XCTAssertEqual(insights.distanceKm, 40, accuracy: 0.0001)
        XCTAssertEqual(insights.energyKWh, 7.3, accuracy: 0.0001)
        XCTAssertEqual(insights.efficiencyKWhPer100Km, 18.25, accuracy: 0.0001)
        XCTAssertTrue(insights.hasCost)
        XCTAssertEqual(insights.cost, 2.92, accuracy: 0.0001)
    }

    func testSummarizeIgnoresTripsBeforePeriodAndActiveTrips() {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let trips = [
            trip(start: since.addingTimeInterval(-1), distanceKm: 100, used: 20),
            trip(start: since.addingTimeInterval(60), distanceKm: 10, used: 2, completed: false),
            trip(start: since.addingTimeInterval(120), distanceKm: 5, used: 1),
        ]

        let insights = TripHistoryInsights.summarize(trips: trips, since: since, pricePerKWh: 0)

        XCTAssertEqual(insights.tripCount, 1)
        XCTAssertEqual(insights.distanceKm, 5, accuracy: 0.0001)
        XCTAssertEqual(insights.energyKWh, 0.8, accuracy: 0.0001)
        XCTAssertFalse(insights.hasCost)
        XCTAssertEqual(insights.cost, 0)
    }

    func testZeroPriceHidesCostAndEmptyInputReturnsEmpty() {
        XCTAssertEqual(TripHistoryInsights.summarize(trips: [], since: .now, pricePerKWh: 0.3), .empty)

        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let insights = TripHistoryInsights.summarize(trips: [trip(start: since)], since: since, pricePerKWh: 0)
        XCTAssertFalse(insights.hasCost)
        XCTAssertEqual(insights.cost, 0)
        XCTAssertEqual(insights.tripCount, 1)
    }

    func testRecoveredEnergyNeverMakesNetEnergyNegative() {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let insights = TripHistoryInsights.summarize(
            trips: [trip(start: since, distanceKm: 10, used: 1, recovered: 5)], since: since, pricePerKWh: 0.5)
        XCTAssertEqual(insights.energyKWh, 0, accuracy: 0.0001)
        XCTAssertEqual(insights.efficiencyKWhPer100Km, 0, accuracy: 0.0001)
    }

    func testStartOfMonthStripsDayAndTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14
        let start = TripHistoryInsights.startOfMonth(containing: date, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: start)
        XCTAssertEqual(components.year, 2023)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 1)
    }
}
