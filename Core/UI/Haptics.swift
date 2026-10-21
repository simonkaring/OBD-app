import Foundation

#if os(iOS)
import UIKit
#endif

/// Small semantic wrapper around UIKit feedback generators.
///
/// Haptics are only played while the app is in the foreground: recordings start
/// and stop automatically, so a feedback call from a background telemetry tick
/// must not fire. The macOS/no-op path keeps every call site free of platform
/// conditionals.
public enum Haptics {
    @MainActor
    public static func impact() {
        #if os(iOS)
        guard isActive else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    @MainActor
    public static func selection() {
        #if os(iOS)
        guard isActive else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    @MainActor
    public static func success() {
        #if os(iOS)
        guard isActive else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    @MainActor
    public static func warning() {
        #if os(iOS)
        guard isActive else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    @MainActor
    public static func error() {
        #if os(iOS)
        guard isActive else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    #if os(iOS)
    @MainActor
    private static var isActive: Bool {
        UIApplication.shared.applicationState == .active
    }
    #endif
}
