#if os(iOS) && canImport(ActivityKit)
// ActivityKit predates strict concurrency annotations; `Activity` is documented as
// thread-safe but the SDK does not mark it Sendable yet.
@preconcurrency import ActivityKit
import Foundation

/// Owns the single VoltLink Live Activity.
///
/// One activity at a time: charging takes precedence over a trip, since users care
/// about charge rate while plugged in. Updates are throttled because telemetry can
/// publish several times per second while Live Activities should update a few times
/// per minute at most.
@MainActor
public final class LiveActivityCoordinator {
    public static let shared = LiveActivityCoordinator()
    public static let enabledKey = "liveActivitiesEnabled"

    private var activity: Activity<VoltLinkActivityAttributes>?
    private var activeMode: VoltLinkActivityAttributes.Mode?
    private var startedAt = Date()
    private var lastUpdate = Date.distantPast
    private static let minimumUpdateInterval: TimeInterval = 5

    public init() {}

    public func update(snapshot: SharedTelemetrySnapshot, chargingActive: Bool, tripActive: Bool) {
        guard (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) ?? true else {
            end()
            return
        }

        guard let mode: VoltLinkActivityAttributes.Mode = chargingActive ? .charging : (tripActive ? .trip : nil) else {
            end()
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = VoltLinkActivityAttributes.ContentState(
            mode: mode,
            socPct: snapshot.socPct,
            powerKW: snapshot.powerKW,
            speedKmH: snapshot.speedKmH,
            distanceKm: snapshot.distanceKm,
            startedAt: mode == activeMode ? startedAt : Date(),
            units: snapshot.units
        )

        if activity == nil || activeMode != mode {
            end()
            start(mode: mode, state: state, vehicleName: snapshot.vehicleName)
            return
        }

        guard let activity, Date().timeIntervalSince(lastUpdate) >= Self.minimumUpdateInterval else { return }
        lastUpdate = Date()
        Task { @MainActor [state] in
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    public func end() {
        guard let activity else { return }
        self.activity = nil
        activeMode = nil
        lastUpdate = .distantPast
        Task { @MainActor in
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func start(mode: VoltLinkActivityAttributes.Mode, state: VoltLinkActivityAttributes.ContentState, vehicleName: String) {
        let attributes = VoltLinkActivityAttributes(vehicleName: vehicleName)
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            activeMode = mode
            startedAt = state.startedAt
            lastUpdate = Date()
        } catch {
            // Live Activities can be disabled per app or by the system; the app keeps
            // running normally without one.
            activity = nil
            activeMode = nil
        }
    }
}
#endif
