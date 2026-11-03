import Foundation
import SwiftData

/// Persists live state-of-health readings into a per-day history.
///
/// Called from the telemetry stream rather than at session boundaries so a car whose adapter
/// reconnects mid-drive still gets a reading that day. The recorder both throttles to one row
/// per vehicle per calendar day and rejects implausible values, so a decoding glitch cannot
/// plant a fake 3% or 140% point on the chart.
@MainActor
public final class BatteryHealthRecorder {
    /// Range outside which a reading is treated as a decode failure instead of battery data.
    public static let plausibleSOH = 50.0...100.0

    public private(set) var lastError: String?
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// Records the reading, replacing today's row for the same vehicle when one exists.
    /// - Returns: `true` when the reading was stored (or updated).
    @discardableResult
    public func record(
        sohPct: Double,
        socPct: Double,
        batteryTempC: Double,
        vehicleName: String,
        at date: Date = .now
    ) -> Bool {
        guard sohPct.isFinite, Self.plausibleSOH.contains(sohPct), !vehicleName.isEmpty else { return false }
        guard let dayStart = calendar.dateInterval(of: .day, for: date)?.start,
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else { return false }

        do {
            // Filter in Swift rather than through a `#Predicate`: the history is at most a few
            // hundred rows, and date/string predicates are easy to get subtly wrong across
            // calendars and store shapes.
            let descriptor = FetchDescriptor<BatteryHealthSampleModel>(
                sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
            let sameDay = try context.fetch(descriptor).first {
                $0.vehicleName == vehicleName && $0.recordedAt >= dayStart && $0.recordedAt < dayEnd
            }

            if let existing = sameDay {
                existing.recordedAt = date
                existing.sohPct = sohPct
                existing.socPct = socPct.isFinite ? socPct : 0
                existing.batteryTempC = batteryTempC.isFinite ? batteryTempC : 0
            } else {
                // Only a new day's row needs the trip total; updating today's reading keeps
                // its stored distance instead of re-scanning every trip.
                let distance = try recordedDistanceKm()
                context.insert(
                    BatteryHealthSampleModel(
                        recordedAt: date,
                        sohPct: sohPct,
                        socPct: socPct.isFinite ? socPct : 0,
                        batteryTempC: batteryTempC.isFinite ? batteryTempC : 0,
                        recordedDistanceKm: distance,
                        vehicleName: vehicleName))
            }
            try context.save()
            lastError = nil
            return true
        } catch {
            lastError = "Battery health history could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    private func recordedDistanceKm() throws -> Double {
        let trips = try context.fetch(FetchDescriptor<TripModel>())
        return trips.reduce(0.0) { total, trip in
            guard trip.endTime != nil, trip.distanceKm.isFinite else { return total }
            return total + max(0, trip.distanceKm)
        }
    }
}
