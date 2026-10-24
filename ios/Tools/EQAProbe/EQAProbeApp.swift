import AppKit
import SwiftUI

@main
struct EQAProbeApp: App {
    @NSApplicationDelegateAdaptor(EQAProbeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("EQA Probe") {
            ProbeView()
                .frame(minWidth: 980, minHeight: 640)
        }
    }
}

private final class EQAProbeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}
