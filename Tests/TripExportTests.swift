import XCTest
@testable import VoltLinkEngine

@MainActor
final class TripExportTests: XCTestCase {

    private func makeTrip() -> TripModel {
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let trip = TripModel(startTime: start, distanceKm: 12.5, startSocPct: 80, vehicleName: "EQA 250")
        trip.endTime = start.addingTimeInterval(900)
        trip.endSocPct = 62
        trip.totalKWhUsed = 3.2
        trip.samples = [
            TelemetryPointModel(timestamp: start, latitude: 55.6763, longitude: 12.5693, speedKmH: 0, powerKW: 0, socPct: 80, batteryTempC: 24),
            TelemetryPointModel(
                timestamp: start.addingTimeInterval(60), latitude: 55.67, longitude: 12.56, speedKmH: 42.5, powerKW: 18.2, socPct: 78.1, batteryTempC: 25),
            // No GPS fix should be exported as empty coordinates, not as (0, 0).
            TelemetryPointModel(timestamp: start.addingTimeInterval(120), latitude: 0, longitude: 0, speedKmH: 50, powerKW: 21, socPct: 77, batteryTempC: 25),
        ]
        return trip
    }

    func testCSVIncludesHeaderOrderedRowsAndEscapedMissingFix() {
        let csv = TripExport.csv(for: makeTrip())
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "timestamp,latitude,longitude,speed_kmh,power_kw,soc_pct,battery_temp_c")
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(csv.contains("55.676300,12.569300"))
        XCTAssertTrue(csv.contains(",50.000,21.000,77.000,"), "Missing fix must leave coordinates empty")
        XCTAssertFalse(csv.contains("0.000000,0.000000"))
    }

    func testGPXContainsValidTrackPointsAndEscapesVehicleName() {
        let trip = makeTrip()
        trip.vehicleName = "EQA & Co <test>"
        let gpx = TripExport.gpx(for: trip)
        XCTAssertTrue(gpx.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(gpx.contains("<gpx version=\"1.1\""))
        XCTAssertTrue(gpx.contains("EQA &amp; Co &lt;test&gt;"))
        XCTAssertEqual(gpx.components(separatedBy: "<trkpt ").count - 1, 2, "Only samples with a GPS fix become track points")
        XCTAssertTrue(gpx.contains("lat=\"55.676300\" lon=\"12.569300\""))
    }

    func testChargingCSVIncludesSessionTotalsAndQuotesLocation() {
        let session = ChargingSessionModel(
            startTime: Date(timeIntervalSince1970: 1_788_000_000),
            startSocPct: 43,
            locationName: "Drejebænken 10, 5260 Odense",
            latitude: 55.35,
            longitude: 10.42)
        session.endTime = session.startTime.addingTimeInterval(2_400)
        session.endSocPct = 82
        session.totalKWhDelivered = 28
        session.peakPowerKW = 78
        session.averagePowerKW = 42

        let csv = TripExport.chargingCSV(for: session)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(csv.contains("\"Drejebænken 10, 5260 Odense\""))
        XCTAssertTrue(csv.contains("40.0,43.000,82.000,28.000,78.000,42.000"))
    }

    func testFilenamesAreStableAndUseTheTripStartDate() {
        let trip = makeTrip()
        XCTAssertEqual(TripExport.filename(for: trip, extension: "gpx"), "VoltLink-Trip-2026-08-29.gpx")

        let session = ChargingSessionModel(startTime: Date(timeIntervalSince1970: 1_788_000_000))
        XCTAssertEqual(TripExport.filename(for: session, extension: "csv"), "VoltLink-Charging-2026-08-29.csv")
    }
}
