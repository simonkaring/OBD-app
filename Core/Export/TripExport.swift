import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// File exports for recorded trips and charging sessions.
///
/// The document types are built from a snapshot of the model's values so the
/// `Transferable` representation never touches a `ModelContext` off the main actor.
public enum TripExport {

    // MARK: - CSV

    public static func csv(for trip: TripModel) -> String {
        var lines = ["timestamp,latitude,longitude,speed_kmh,power_kw,soc_pct,battery_temp_c"]
        lines.reserveCapacity(trip.samples.count + 1)
        for sample in trip.samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            let coordinate: (lat: String, lon: String) =
                sample.hasValidCoordinate
                ? (String(format: "%.6f", sample.latitude), String(format: "%.6f", sample.longitude))
                : ("", "")
            lines.append(
                [
                    iso8601(sample.timestamp),
                    coordinate.lat,
                    coordinate.lon,
                    number(sample.speedKmH),
                    number(sample.powerKW),
                    number(sample.socPct),
                    number(sample.batteryTempC),
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func chargingCSV(for session: ChargingSessionModel) -> String {
        let header = "start_time,end_time,duration_minutes,start_soc_pct,end_soc_pct,energy_kwh,peak_power_kw,average_power_kw,location,latitude,longitude"
        let duration = session.endTime.map { max(0, $0.timeIntervalSince(session.startTime) / 60) }
        let row = [
            iso8601(session.startTime),
            session.endTime.map(iso8601) ?? "",
            duration.map { String(format: "%.1f", $0) } ?? "",
            number(session.startSocPct),
            number(session.endSocPct),
            number(session.totalKWhDelivered),
            number(session.peakPowerKW),
            number(session.averagePowerKW),
            csvField(session.locationName),
            session.latitude.map { String(format: "%.6f", $0) } ?? "",
            session.longitude.map { String(format: "%.6f", $0) } ?? "",
        ].joined(separator: ",")
        return [header, row].joined(separator: "\n") + "\n"
    }

    // MARK: - GPX

    public static func gpx(for trip: TripModel) -> String {
        let name = "\(trip.vehicleName) \(trip.startTime.formatted(date: .abbreviated, time: .shortened))"
        let route = trip.samples
            .filter { $0.hasValidCoordinate }
            .sorted { $0.timestamp < $1.timestamp }
        var points: [String] = []
        points.reserveCapacity(route.count)
        for sample in route {
            points.append(
                """
                      <trkpt lat="\(String(format: "%.6f", sample.latitude))" lon="\(String(format: "%.6f", sample.longitude))">
                        <time>\(iso8601(sample.timestamp))</time>
                        <extensions>
                          <speed>\(number(sample.speedKmH))</speed>
                          <power>\(number(sample.powerKW))</power>
                          <soc>\(number(sample.socPct))</soc>
                        </extensions>
                      </trkpt>
                """)
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="VoltLink" xmlns="http://www.topografix.com/GPX/1/1">
              <metadata>
                <name>\(xmlEscape(name))</name>
                <time>\(iso8601(trip.startTime))</time>
              </metadata>
              <trk>
                <name>\(xmlEscape(name))</name>
                <trkseg>
            \(points.joined(separator: "\n"))
                </trkseg>
              </trk>
            </gpx>

            """
    }

    public static func filename(for trip: TripModel, extension ext: String) -> String {
        let stamp = trip.startTime.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "VoltLink-Trip-\(stamp).\(ext)"
    }

    public static func filename(for session: ChargingSessionModel, extension ext: String) -> String {
        let stamp = session.startTime.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "VoltLink-Charging-\(stamp).\(ext)"
    }

    // MARK: - Formatting helpers

    private static func iso8601(_ date: Date) -> String {
        // `ISO8601FormatStyle` is a value type, unlike the shared mutable
        // `ISO8601DateFormatter` Swift 6 rejects as global state.
        date.formatted(.iso8601)
    }

    private static func number(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%.3f", value)
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Transferable documents

/// GPX share document. `FileRepresentation` writes lazily, only when the share sheet
/// actually asks for the file, so rendering a trip detail view never touches disk.
public struct TripGPXExport: Transferable, Sendable {
    private let filename: String
    private let data: Data

    public init(trip: TripModel) {
        filename = TripExport.filename(for: trip, extension: "gpx")
        data = Data(TripExport.gpx(for: trip).utf8)
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: UTType(filenameExtension: "gpx") ?? .xml) { document in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(document.filename)
            try document.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

public struct TripCSVExport: Transferable, Sendable {
    private let filename: String
    private let data: Data

    public init(trip: TripModel) {
        filename = TripExport.filename(for: trip, extension: "csv")
        data = Data(TripExport.csv(for: trip).utf8)
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { document in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(document.filename)
            try document.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

public struct ChargingCSVExport: Transferable, Sendable {
    private let filename: String
    private let data: Data

    public init(session: ChargingSessionModel) {
        filename = TripExport.filename(for: session, extension: "csv")
        data = Data(TripExport.chargingCSV(for: session).utf8)
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { document in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(document.filename)
            try document.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
