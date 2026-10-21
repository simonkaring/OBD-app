import Foundation

/// Aggregates completed trips into the period summary shown on the Log tab.
///
/// Kept as a value type outside the view so the arithmetic (net energy, weighted
/// efficiency, cost) is testable without SwiftUI or a live manager.
public struct TripHistoryInsights: Sendable, Equatable {
    public let tripCount: Int
    public let distanceKm: Double
    /// Net energy drawn from the pack (used minus recovered), never negative.
    public let energyKWh: Double
    public let efficiencyKWhPer100Km: Double
    public let cost: Double
    public let hasCost: Bool

    public init(tripCount: Int, distanceKm: Double, energyKWh: Double, efficiencyKWhPer100Km: Double, cost: Double, hasCost: Bool) {
        self.tripCount = tripCount
        self.distanceKm = distanceKm
        self.energyKWh = energyKWh
        self.efficiencyKWhPer100Km = efficiencyKWhPer100Km
        self.cost = cost
        self.hasCost = hasCost
    }

    public static let empty = TripHistoryInsights(
        tripCount: 0, distanceKm: 0, energyKWh: 0, efficiencyKWhPer100Km: 0, cost: 0, hasCost: false)

    /// - Parameters:
    ///   - trips: All recorded trips; incomplete (active) trips are ignored.
    ///   - since: Inclusive start of the reporting period.
    ///   - pricePerKWh: User's electricity price; `0` disables the cost estimate.
    public static func summarize(trips: [TripModel], since: Date, pricePerKWh: Double = 0) -> TripHistoryInsights {
        let completed = trips.filter { trip in
            guard trip.endTime != nil, trip.startTime >= since else { return false }
            return trip.distanceKm.isFinite && trip.totalKWhUsed.isFinite
        }
        guard !completed.isEmpty else { return .empty }

        var distance = 0.0
        var energy = 0.0
        for trip in completed {
            distance += max(0, trip.distanceKm)
            let recovered = trip.totalKWhRecovered ?? 0
            energy += max(0, trip.totalKWhUsed - (recovered.isFinite ? max(0, recovered) : 0))
        }

        let efficiency = distance > 0.1 ? (energy / distance) * 100 : 0
        let price = pricePerKWh.isFinite && pricePerKWh > 0 ? pricePerKWh : 0
        return TripHistoryInsights(
            tripCount: completed.count,
            distanceKm: distance,
            energyKWh: energy,
            efficiencyKWhPer100Km: efficiency,
            cost: energy * price,
            hasCost: price > 0
        )
    }

    /// Start of the current calendar month, used as the default reporting period.
    public static func startOfMonth(containing date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
