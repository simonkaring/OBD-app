import Foundation

/// One state-of-health reading reduced to just the values the trend math needs, so the
/// summary is testable without SwiftData or SwiftUI.
public struct BatteryHealthPoint: Sendable, Equatable {
    public let date: Date
    public let sohPct: Double

    public init(date: Date, sohPct: Double) {
        self.date = date
        self.sohPct = sohPct
    }
}

/// Summary of the battery health history shown on the Charging tab.
///
/// `annualizedChangePct` needs at least two weeks of observations before it is reported;
/// extrapolating a multi-year loss rate from a couple of days produces nonsense.
public struct BatteryHealthTrend: Sendable, Equatable {
    public static let minimumAnnualizationDays = 14.0

    public let sampleCount: Int
    public let firstSohPct: Double
    public let latestSohPct: Double
    public let observedDays: Double
    /// Percentage points gained or lost since the first reading (negative = degradation).
    public let changePct: Double
    /// Percentage points per year, when the history is long enough to extrapolate.
    public let annualizedChangePct: Double?

    public init(
        sampleCount: Int, firstSohPct: Double, latestSohPct: Double, observedDays: Double, changePct: Double,
        annualizedChangePct: Double?
    ) {
        self.sampleCount = sampleCount
        self.firstSohPct = firstSohPct
        self.latestSohPct = latestSohPct
        self.observedDays = observedDays
        self.changePct = changePct
        self.annualizedChangePct = annualizedChangePct
    }

    /// Returns nil until there are at least two usable readings.
    public static func summarize(points: [BatteryHealthPoint]) -> BatteryHealthTrend? {
        let readings =
            points
            .filter { $0.sohPct.isFinite && (1...100).contains($0.sohPct) && $0.date.timeIntervalSince1970.isFinite }
            .sorted { $0.date < $1.date }
        guard readings.count >= 2, let first = readings.first, let last = readings.last else { return nil }

        let observedDays = max(0, last.date.timeIntervalSince(first.date) / 86_400)
        let change = last.sohPct - first.sohPct
        let annualized =
            observedDays >= minimumAnnualizationDays
            ? (change / observedDays) * 365.0
            : nil

        return BatteryHealthTrend(
            sampleCount: readings.count,
            firstSohPct: first.sohPct,
            latestSohPct: last.sohPct,
            observedDays: observedDays,
            changePct: change,
            annualizedChangePct: annualized
        )
    }
}
