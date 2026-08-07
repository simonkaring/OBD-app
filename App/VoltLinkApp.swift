import SwiftUI
import SwiftData

@main
struct VoltLinkApp: App {
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

struct MainTabView: View {
    @EnvironmentObject private var vehicleData: VehicleDataManager
    @EnvironmentObject private var tripTracker: TripTrackingManager
    @EnvironmentObject private var dtcService: DTCScannerService

    var body: some View {
        TabView {
            DashboardView(vehicleData: vehicleData, tripTracker: tripTracker)
                .tabItem {
                    Label("Telemetry", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }

            DiagnosticsView(dtcService: dtcService, vehicleData: vehicleData)
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }

            TripHistoryView(tripTracker: tripTracker)
                .tabItem {
                    Label("Trips", systemImage: "road.lanes")
                }

            ChargingLiveView(vehicleData: vehicleData)
                .tabItem {
                    Label("Charging", systemImage: "bolt.batteryblock")
                }

            SettingsView(vehicleData: vehicleData)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .accentColor(Theme.electricCyan)
    }
}
