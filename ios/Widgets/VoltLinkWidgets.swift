import SwiftUI
import WidgetKit

@main
struct VoltLinkWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoltLinkStatusWidget()
        #if canImport(ActivityKit)
        VoltLinkLiveActivityWidget()
        #endif
    }
}
