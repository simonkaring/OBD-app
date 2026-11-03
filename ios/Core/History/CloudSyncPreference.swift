import Foundation

/// Opt-in setting for mirroring recorded history into the user's private iCloud database.
///
/// Off by default: a local OBD recorder must not upload vehicle history without the owner
/// asking for it. The container is built once at launch, so toggling this takes effect the
/// next time the app starts.
public enum CloudSyncPreference {
    public static let enabledKey = "icloudSyncEnabled"
    /// The CloudKit container declared in `App/VoltLink.entitlements`.
    public static let containerIdentifier = "iCloud.com.simonkaring.voltlink"

    public static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }
}
