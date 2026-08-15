import SwiftUI
import SwiftData

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication || connectingSceneSession.role.rawValue == "CPTemplateApplicationSceneSessionRoleApplication" {
            let config = UISceneConfiguration(
                name: "CarPlaySceneConfiguration",
                sessionRole: connectingSceneSession.role
            )
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        
        let config = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        return config
    }
}

@main
struct VoltLinkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(env.vehicleData)
                .environmentObject(env.tripTracker)
                .environmentObject(env.dtcService)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [TripModel.self, TelemetryPointModel.self, ChargingSessionModel.self, SavedDTCModel.self])
    }
}
#endif

struct MainTabView: View {
    @EnvironmentObject private var vehicleData: VehicleDataManager
    @EnvironmentObject private var tripTracker: TripTrackingManager
    @EnvironmentObject private var dtcService: DTCScannerService
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Int = 0
    @State private var isBannerDismissedManually: Bool = false

    private var isDisconnectedBannerActive: Bool {
        !vehicleData.isDemoMode && !vehicleData.connectionState.isConnected && !isBannerDismissedManually
    }

    @ViewBuilder
    private func withBannerInset<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .overlay(alignment: .bottom) {
                if isDisconnectedBannerActive {
                    FloatingConnectionBanner(
                        onConnectTap: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedTab = 4
                            }
                        },
                        onDismissTap: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isBannerDismissedManually = true
                            }
                        }
                    )
                    .padding(.bottom, 6)
                    .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            withBannerInset {
                DashboardView(vehicleData: vehicleData, tripTracker: tripTracker)
            }
            .tabItem {
                Label("Telemetry", systemImage: "gauge.with.dots.needle.bottom.50percent")
            }
            .tag(0)

            withBannerInset {
                DiagnosticsView(dtcService: dtcService, vehicleData: vehicleData)
            }
            .tabItem {
                Label("Diagnostics", systemImage: "stethoscope")
            }
            .tag(1)

            withBannerInset {
                TripHistoryView(tripTracker: tripTracker)
            }
            .tabItem {
                Label("Trips", systemImage: "road.lanes")
            }
            .tag(2)

            withBannerInset {
                ChargingLiveView(vehicleData: vehicleData)
            }
            .tabItem {
                Label("Charging", systemImage: "bolt.batteryblock")
            }
            .tag(3)

            withBannerInset {
                SettingsView(vehicleData: vehicleData, tripTracker: tripTracker)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(4)
        }
        .accentColor(Theme.electricCyan)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isDisconnectedBannerActive)
        .onChange(of: vehicleData.isDemoMode) { _, _ in
            isBannerDismissedManually = false
        }
        .onAppear {
            tripTracker.modelContext = modelContext
        }
    }
}

