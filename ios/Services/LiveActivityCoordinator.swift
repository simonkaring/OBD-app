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
    /// A previous process can leave an activity running (app killed mid-session). Adopt it
    /// once per launch instead of requesting a second one.
    private var didAttemptAdoption = false
    /// Fallback elapsed origin for a session whose recorder has no start time yet.
    private var activityStartedAt = Date()
    private var lastUpdate = Date.distantPast
    private static let minimumUpdateInterval: TimeInterval = 5
    /// A Live Activity the app never updates again (app killed, adapter lost) must not
    /// keep advertising a frozen charge rate: iOS dims it after the snapshot TTL.
    private static let staleAfter: TimeInterval = SharedTelemetrySnapshot.maximumAge

    private func content(for state: VoltLinkActivityAttributes.ContentState, at date: Date = .now)
        -> ActivityContent<VoltLinkActivityAttributes.ContentState>
    {
        ActivityContent(state: state, staleDate: date.addingTimeInterval(Self.staleAfter))
    }

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

        // The recorder owns the clock: a trip or charging session started before the app
        // was relaunched still shows its full elapsed time. The fallback only lasts until
        // the recorder publishes its start time.
        let startedAt = snapshot.activeSessionStartedAt ?? (mode == activeMode ? activityStartedAt : Date())
        let state = VoltLinkActivityContent.make(mode: mode, snapshot: snapshot, startedAt: startedAt)

        if activity == nil || activeMode != mode {
            end()
            activityStartedAt = startedAt
            start(mode: mode, state: state, vehicleName: snapshot.vehicleName)
            return
        }

        guard let activity, Date().timeIntervalSince(lastUpdate) >= Self.minimumUpdateInterval else { return }
        lastUpdate = Date()
        let content = content(for: state)
        Task { @MainActor in
            await activity.update(content)
        }
    }

    public func end() {
        didAttemptAdoption = true
        self.activity = nil
        activeMode = nil
        lastUpdate = .distantPast
        // End every activity, not just one held in memory: after a relaunch the previous
        // process's activity is still on the Lock Screen and would otherwise linger until
        // its stale date.
        for running in Activity<VoltLinkActivityAttributes>.activities {
            Task { @MainActor in
                await running.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func start(mode: VoltLinkActivityAttributes.Mode, state: VoltLinkActivityAttributes.ContentState, vehicleName: String) {
        let attributes = VoltLinkActivityAttributes(vehicleName: vehicleName)
        let content = content(for: state)

        if !didAttemptAdoption {
            didAttemptAdoption = true
            let running = Activity<VoltLinkActivityAttributes>.activities
            if let existing = running.first {
                // Take over the activity instead of stacking a duplicate on the Lock Screen.
                activity = existing
                activeMode = mode
                lastUpdate = Date()
                for extra in running.dropFirst() {
                    Task { @MainActor in
                        await extra.end(nil, dismissalPolicy: .immediate)
                    }
                }
                Task { @MainActor in
                    await existing.update(content)
                }
                return
            }
        }

        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            activeMode = mode
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
