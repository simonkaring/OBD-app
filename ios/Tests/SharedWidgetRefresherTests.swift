import XCTest

@testable import VoltLinkEngine

/// Guards the app-driven widget reload budget: telemetry publishes several times per
/// second, while WidgetKit only wants a new timeline when something it draws changed.
@MainActor
final class SharedWidgetRefresherTests: XCTestCase {
    private static var reloads = 0
    private static var originalReload: (@MainActor () -> Void)?

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        Self.originalReload = SharedWidgetRefresher.performReload
        SharedWidgetRefresher.reset()
        Self.reloads = 0
        SharedWidgetRefresher.performReload = { Self.reloads += 1 }
    }

    override func tearDown() {
        if let originalReload = Self.originalReload {
            SharedWidgetRefresher.performReload = originalReload
        }
        Self.originalReload = nil
        SharedWidgetRefresher.reset()
        super.tearDown()
    }

    private func snapshot(soc: Double = 50, speedKmH: Double = 0, isCharging: Bool = false) -> SharedTelemetrySnapshot {
        SharedTelemetrySnapshot(vehicleName: "EQA", socPct: soc, speedKmH: speedKmH, isCharging: isCharging, updatedAt: base)
    }

    func testFirstSnapshotRequestsReload() {
        XCTAssertTrue(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(), at: base))
        XCTAssertEqual(Self.reloads, 1)
    }

    func testUnchangedSnapshotRequestsNothingEvenMinutesLater() {
        XCTAssertTrue(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(), at: base))
        XCTAssertFalse(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(), at: base.addingTimeInterval(600)))
        XCTAssertEqual(Self.reloads, 1)
    }

    func testChangeInsideTheMinimumIntervalIsDeferred() {
        XCTAssertTrue(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(), at: base))
        XCTAssertFalse(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(soc: 51), at: base.addingTimeInterval(10)))
        // The deferred change still counts once the interval has passed.
        XCTAssertTrue(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(soc: 51), at: base.addingTimeInterval(61)))
        XCTAssertEqual(Self.reloads, 2)
    }

    func testSubPercentDriftDoesNotReload() {
        XCTAssertTrue(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(soc: 50), at: base))
        XCTAssertFalse(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(soc: 50.2), at: base.addingTimeInterval(120)))
        XCTAssertEqual(Self.reloads, 1)
    }

    func testStateFlagChangeReloads() {
        XCTAssertTrue(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(), at: base))
        XCTAssertTrue(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(isCharging: true), at: base.addingTimeInterval(61)))
        XCTAssertEqual(Self.reloads, 2)
    }

    func testForceIgnoresThrottleAndChangeDetection() {
        XCTAssertTrue(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(), at: base))
        XCTAssertTrue(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(), at: base.addingTimeInterval(1), force: true))
        XCTAssertEqual(Self.reloads, 2)
    }

    func testUnitChangeReloadsEvenWhenValuesAreEqual() {
        XCTAssertTrue(SharedWidgetRefresher.refreshIfNeeded(for: snapshot(speedKmH: 100), at: base))

        var imperial = snapshot(speedKmH: 100)
        imperial.units = SharedDisplayUnits(distance: .miles)
        XCTAssertTrue(SharedWidgetRefresher.refreshIfNeeded(for: imperial, at: base.addingTimeInterval(61)))
        XCTAssertEqual(Self.reloads, 2)
    }
}
