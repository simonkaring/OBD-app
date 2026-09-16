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
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false
    @StateObject private var env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(env)
                .environmentObject(env.vehicleData)
                .environmentObject(env.tripTracker)
                .environmentObject(env.chargingTracker)
                .environmentObject(env.dtcService)
                .preferredColorScheme(.dark)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenAwake }
                .onChange(of: keepScreenAwake) { _, enabled in
                    UIApplication.shared.isIdleTimerDisabled = enabled
                }
        }
        // Container is owned by AppEnvironment so CarPlay-only launches persist too.
        .modelContainer(env.modelContainer)
    }
}
#endif

struct MainTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var vehicleData: VehicleDataManager
    @EnvironmentObject private var tripTracker: TripTrackingManager
    @EnvironmentObject private var chargingTracker: ChargingTrackingManager
    @EnvironmentObject private var dtcService: DTCScannerService
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
        if vehicleData.hasSelectedVehicle || vehicleData.isDemoMode {
            TabView(selection: $selectedTab) {
                withBannerInset {
                    DashboardView(vehicleData: vehicleData, tripTracker: tripTracker)
                }
                .tabItem {
                    Label("Telemetry", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                .tag(0)

                withBannerInset {
                    TripHistoryView(tripTracker: tripTracker)
                }
                .tabItem {
                    Label("Log", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)

                withBannerInset {
                    ChargingLiveView(vehicleData: vehicleData)
                }
                .tabItem {
                    Label("Charging", systemImage: "bolt.batteryblock")
                }
                .tag(2)

                withBannerInset {
                    DiagnosticsView(dtcService: dtcService, vehicleData: vehicleData)
                }
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
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
            .tint(Theme.electricCyan)
            .safeAreaInset(edge: .top) {
                if let error = env.storageWarning ?? tripTracker.persistenceError ?? chargingTracker.persistenceError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                        if env.storageWarning == nil {
                            Button("Retry Saving History") {
                                tripTracker.retrySaving()
                                chargingTracker.retrySaving()
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.highPowerAmber.opacity(0.2))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isDisconnectedBannerActive)
            .onChange(of: vehicleData.isDemoMode) { _, _ in
                isBannerDismissedManually = false
            }
            // The trip/charging model contexts are wired in `AppEnvironment.init`, not here:
            // a CarPlay-only launch never presents this view.
        } else {
            // The picker owns its own NavigationStack and surfaces the demo/generic-EV
            // entries as a top section when isFirstRun — no wrapper needed here.
            VehicleProfilePickerSheet(vehicleData: vehicleData, isFirstRun: true)
        }
    }
}
