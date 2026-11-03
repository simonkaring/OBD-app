import SwiftData
import XCTest

@testable import VoltLinkEngine

final class BatteryHealthTrendTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(daysAfter start: Date, _ days: Double) -> Date {
        start.addingTimeInterval(days * 86_400)
    }

    func testSummarizesLossSinceFirstReading() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trend = try XCTUnwrap(
            BatteryHealthTrend.summarize(points: [
                BatteryHealthPoint(date: start, sohPct: 99.2),
                BatteryHealthPoint(date: date(daysAfter: start, 30), sohPct: 97.7),
            ]))
        XCTAssertEqual(trend.sampleCount, 2)
        XCTAssertEqual(trend.firstSohPct, 99.2, accuracy: 0.001)
        XCTAssertEqual(trend.latestSohPct, 97.7, accuracy: 0.001)
        XCTAssertEqual(trend.changePct, -1.5, accuracy: 0.001)
        XCTAssertEqual(trend.observedDays, 30, accuracy: 0.001)
        let annualized = try XCTUnwrap(trend.annualizedChangePct)
        XCTAssertEqual(annualized, -18.25, accuracy: 0.001)
    }

    func testDoesNotAnnualizeShortHistories() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trend = try XCTUnwrap(
            BatteryHealthTrend.summarize(points: [
                BatteryHealthPoint(date: start, sohPct: 99),
                BatteryHealthPoint(date: date(daysAfter: start, 3), sohPct: 98.9),
            ]))
        XCTAssertNil(trend.annualizedChangePct)
        XCTAssertEqual(trend.observedDays, 3, accuracy: 0.001)
    }

    func testNeedsTwoUsableReadings() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(BatteryHealthTrend.summarize(points: []))
        XCTAssertNil(BatteryHealthTrend.summarize(points: [BatteryHealthPoint(date: date, sohPct: 99)]))
        XCTAssertNil(
            BatteryHealthTrend.summarize(points: [
                BatteryHealthPoint(date: date, sohPct: 99),
                BatteryHealthPoint(date: date.addingTimeInterval(86_400), sohPct: 140),
            ]))
    }

    func testSortsOutOfOrderReadings() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trend = try XCTUnwrap(
            BatteryHealthTrend.summarize(points: [
                BatteryHealthPoint(date: date(daysAfter: start, 20), sohPct: 96),
                BatteryHealthPoint(date: start, sohPct: 99),
            ]))
        XCTAssertEqual(trend.firstSohPct, 99, accuracy: 0.001)
        XCTAssertEqual(trend.latestSohPct, 96, accuracy: 0.001)
        XCTAssertEqual(trend.changePct, -3, accuracy: 0.001)
    }
}

@MainActor
final class BatteryHealthRecorderTests: XCTestCase {
    /// Noon on a fixed day: late-evening UTC timestamps cross local midnight in many
    /// time zones and would create a second day's row for the wrong reason.
    private var noon: Date {
        Calendar.current.date(from: DateComponents(year: 2024, month: 5, day: 10, hour: 12))!
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: VoltLinkCurrentSchema.versioned)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    func testKeepsOneSamplePerDayAndUpdatesIt() throws {
        let context = try makeContext()
        let recorder = BatteryHealthRecorder(context: context)
        let day = noon

        XCTAssertTrue(recorder.record(sohPct: 98.4, socPct: 55, batteryTempC: 24, vehicleName: "EQA", at: day))
        XCTAssertTrue(
            recorder.record(
                sohPct: 98.1, socPct: 71, batteryTempC: 27, vehicleName: "EQA", at: day.addingTimeInterval(3_600)))

        let samples = try context.fetch(FetchDescriptor<BatteryHealthSampleModel>())
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.sohPct, 98.1)
        XCTAssertEqual(samples.first?.socPct, 71)
    }

    func testAddsANewSampleOnTheNextDay() throws {
        let context = try makeContext()
        let recorder = BatteryHealthRecorder(context: context)
        let day = noon

        XCTAssertTrue(recorder.record(sohPct: 98.4, socPct: 55, batteryTempC: 24, vehicleName: "EQA", at: day))
        XCTAssertTrue(
            recorder.record(sohPct: 98.2, socPct: 60, batteryTempC: 25, vehicleName: "EQA", at: day.addingTimeInterval(86_400)))

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BatteryHealthSampleModel>()), 2)
    }

    func testSeparatesVehiclesAndRejectsImplausibleValues() throws {
        let context = try makeContext()
        let recorder = BatteryHealthRecorder(context: context)
        let day = noon

        XCTAssertTrue(recorder.record(sohPct: 97, socPct: 50, batteryTempC: 22, vehicleName: "EQA", at: day))
        XCTAssertTrue(recorder.record(sohPct: 91, socPct: 50, batteryTempC: 22, vehicleName: "ID.4", at: day))
        XCTAssertFalse(recorder.record(sohPct: 140, socPct: 50, batteryTempC: 22, vehicleName: "EQA", at: day))
        XCTAssertFalse(recorder.record(sohPct: 3, socPct: 50, batteryTempC: 22, vehicleName: "EQA", at: day))

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BatteryHealthSampleModel>()), 2)
    }

    func testStoresDistanceFromCompletedTripsOnly() throws {
        let context = try makeContext()
        let recorder = BatteryHealthRecorder(context: context)

        let complete = TripModel(startTime: Date(timeIntervalSince1970: 1_700_000_000), distanceKm: 42)
        complete.endTime = complete.startTime.addingTimeInterval(3_600)
        context.insert(complete)
        let active = TripModel(startTime: Date(timeIntervalSince1970: 1_700_001_000), distanceKm: 99)
        context.insert(active)
        try context.save()

        XCTAssertTrue(recorder.record(sohPct: 97.5, socPct: 40, batteryTempC: 20, vehicleName: "EQA"))
        let sample = try XCTUnwrap(context.fetch(FetchDescriptor<BatteryHealthSampleModel>()).first)
        XCTAssertEqual(sample.recordedDistanceKm, 42, accuracy: 0.001)
    }
}
