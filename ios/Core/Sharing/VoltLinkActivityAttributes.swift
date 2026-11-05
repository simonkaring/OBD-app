#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity shared between the app (which starts/updates it) and the widget
/// extension (which renders the Lock Screen / Dynamic Island presentation).
@available(iOS 16.2, *)
public struct VoltLinkActivityAttributes: ActivityAttributes {
    /// The content lives in `Core/Sharing` so `swift test` can exercise it on macOS;
    /// these typealiases satisfy the protocol's nested requirements.
    public typealias Mode = VoltLinkActivityContent.Mode
    public typealias ContentState = VoltLinkActivityContent

    public var vehicleName: String

    public init(vehicleName: String) {
        self.vehicleName = vehicleName
    }
}
#endif
