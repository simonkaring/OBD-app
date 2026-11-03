import XCTest

@testable import VoltLinkEngine

@MainActor
final class ServiceReminderTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ServiceReminderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testStoresAndReadsSnapshotPerVehicle() {
        let monitor = ServiceReminderMonitor(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNil(monitor.snapshot(for: "EQA"))
        let stored = monitor.observe(distanceKm: 4200, vehicleName: "EQA", at: now)
        XCTAssertEqual(stored, ServiceIntervalSnapshot(remainingKm: 4200, observedAt: now))
        XCTAssertEqual(monitor.snapshot(for: "EQA")?.remainingKm, 4200)
        XCTAssertNil(monitor.snapshot(for: "ID.4"))

        monitor.observe(distanceKm: 900, vehicleName: "ID.4", at: now)
        XCTAssertEqual(monitor.snapshot(for: "EQA")?.remainingKm, 4200)
        XCTAssertEqual(monitor.snapshot(for: "ID.4")?.remainingKm, 900)
    }

    func testRejectsImplausibleReadings() {
        let monitor = ServiceReminderMonitor(defaults: defaults)
        XCTAssertNil(monitor.observe(distanceKm: .nan, vehicleName: "EQA"))
        XCTAssertNil(monitor.observe(distanceKm: -5, vehicleName: "EQA"))
        XCTAssertNil(monitor.observe(distanceKm: 200_000, vehicleName: "EQA"))
        XCTAssertNil(monitor.observe(distanceKm: 1000, vehicleName: ""))
        XCTAssertNil(monitor.snapshot(for: "EQA"))
    }

    func testRemindsOnlyBelowThresholdWhenEnabled() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(
            ServiceReminderMonitor.shouldRemind(
                remainingKm: 800, thresholdKm: 1000, lastNotifiedAt: nil, enabled: true, at: now))
        XCTAssertFalse(
            ServiceReminderMonitor.shouldRemind(
                remainingKm: 1200, thresholdKm: 1000, lastNotifiedAt: nil, enabled: true, at: now))
        XCTAssertFalse(
            ServiceReminderMonitor.shouldRemind(
                remainingKm: 800, thresholdKm: 1000, lastNotifiedAt: nil, enabled: false, at: now))
    }

    func testCooldownSuppressesRepeatedReminders() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoDaysAgo = now.addingTimeInterval(-2 * 86_400)
        let eightDaysAgo = now.addingTimeInterval(-8 * 86_400)

        XCTAssertFalse(
            ServiceReminderMonitor.shouldRemind(
                remainingKm: 800, thresholdKm: 1000, lastNotifiedAt: twoDaysAgo, enabled: true, at: now))
        XCTAssertTrue(
            ServiceReminderMonitor.shouldRemind(
                remainingKm: 800, thresholdKm: 1000, lastNotifiedAt: eightDaysAgo, enabled: true, at: now))
    }

    func testThresholdFallsBackToDefaultForUnknownValues() {
        let monitor = ServiceReminderMonitor(defaults: defaults)
        XCTAssertEqual(monitor.thresholdKm, ServiceReminderMonitor.defaultThresholdKm)

        defaults.set(2000.0, forKey: ServiceReminderMonitor.Key.thresholdKm)
        XCTAssertEqual(monitor.thresholdKm, 2000)

        defaults.set(1234.0, forKey: ServiceReminderMonitor.Key.thresholdKm)
        XCTAssertEqual(monitor.thresholdKm, ServiceReminderMonitor.defaultThresholdKm)
    }
}
