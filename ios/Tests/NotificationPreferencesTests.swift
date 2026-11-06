import Foundation
import XCTest

@testable import VoltLinkEngine

/// The alert switches are opt-in: a fresh install must read every key as off. Otherwise the
/// Settings toggles show ON while permission is never requested (it is only requested from a
/// toggle's setter) and every posted request is silently dropped.
final class NotificationPreferencesTests: XCTestCase {
    @MainActor
    func testNotificationsDefaultOffUntilTheUserEnablesThem() throws {
        let suiteName = "VoltLinkNotificationPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = NotificationService(defaults: defaults)
        let keys = [
            NotificationService.PreferenceKey.chargingFinished,
            NotificationService.PreferenceKey.adapterDisconnected,
            NotificationService.PreferenceKey.faultCodes,
            NotificationService.PreferenceKey.chargeTargetReached,
            NotificationService.PreferenceKey.serviceDue,
        ]
        for key in keys {
            XCTAssertFalse(service.isEnabled(key), "\(key) must default to off")
        }

        defaults.set(true, forKey: NotificationService.PreferenceKey.faultCodes)
        XCTAssertTrue(service.isEnabled(NotificationService.PreferenceKey.faultCodes))
    }
}
