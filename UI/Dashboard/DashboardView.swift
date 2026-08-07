import SwiftUI

public struct DashboardView: View {
    @ObservedObject public var vehicleData: VehicleDataManager
    @ObservedObject public var tripTracker: TripTrackingManager

    @State private var telemetryHistory: [TelemetrySnapshot] = []
    @State private var showHUDMode = false
    @State private var showDemoControls = false
    @State private var showCustomization = false
    @AppStorage("dashboardLayout") private var layout: DashboardLayout = .default

    public init(vehicleData: VehicleDataManager, tripTracker: TripTrackingManager) {
        self.vehicleData = vehicleData
        self.tripTracker = tripTracker
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Connection Header Bar
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(vehicleData.connectionState.isConnected ? Theme.regenGreen : Theme.criticalRed)
                                    .frame(width: 10, height: 10)
                                Text(vehicleData.isDemoMode ? "DEMO MODE (\(vehicleData.selectedProfile.vehicleName))" : "CONNECTED (Vgate iCar Pro 2S)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.textPrimary)
                            }
                            Spacer()

                            if vehicleData.isDemoMode, vehicleData.obdConnection is MockOBDAdapter {
                                Button {
                                    showDemoControls = true
                                } label: {
                                    Label("Controls", systemImage: "slider.horizontal.3")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Theme.electricCyan.opacity(0.2))
                                        .foregroundColor(Theme.electricCyan)
                                        .cornerRadius(8)
                                }
                            }

                            Button {
                                showCustomization = true
                            } label: {
                                Image(systemName: "slider.horizontal.2.gtsquare")
                                    .foregroundColor(Theme.electricCyan)
                                    .padding(8)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }

                            Button {
                                showHUDMode = true
                            } label: {
                                Image(systemName: "sunglasses.fill")
                                    .foregroundColor(Theme.electricCyan)
                                    .padding(8)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal)

                        // Customizable widget grid
                        ForEach(Array(packDashboardWidgetsIntoRows(layout.widgets).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 12) {
                                ForEach(row) { widget in
                                    DashboardWidgetTile(
                                        config: widget,
                                        snapshot: vehicleData.latestTelemetry,
                                        profile: vehicleData.selectedProfile,
                                        telemetryHistory: telemetryHistory
                                    )
                                    .frame(maxWidth: .infinity)
                                    .frame(height: widget.size.height)
                                }
                            }
                            .padding(.horizontal)
                        }

                        // Trip Recording Control Bar
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tripTracker.isRecordingTrip ? "TRIP RECORDING ACTIVE" : "TRIP READY")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(tripTracker.isRecordingTrip ? Theme.regenGreen : Theme.textSecondary)
                                Text(String(format: "%.1f km logged", tripTracker.currentTrip?.distanceKm ?? 0.0))
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.textPrimary)
                            }

                            Spacer()

                            Button {
                                if tripTracker.isRecordingTrip {
                                    tripTracker.stopTrip(endSoc: vehicleData.latestTelemetry.stateOfChargePct)
                                } else {
                                    tripTracker.startTrip(startSoc: vehicleData.latestTelemetry.stateOfChargePct)
                                }
                            } label: {
                                Text(tripTracker.isRecordingTrip ? "Stop Trip" : "Start Trip")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(tripTracker.isRecordingTrip ? Theme.criticalRed : Theme.electricCyan)
                                    .foregroundColor(.black)
                                    .cornerRadius(10)
                            }
                        }
                        .padding()
                        .glassCard()
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
            .onReceive(vehicleData.$latestTelemetry) { snap in
                telemetryHistory.append(snap)
                if telemetryHistory.count > 50 {
                    telemetryHistory.removeFirst()
                }
                if tripTracker.isRecordingTrip {
                    tripTracker.recordSnapshot(snap)
                }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showHUDMode) {
                HUDModeView(
                    speedKmH: vehicleData.latestTelemetry.speedKmH,
                    powerKW: vehicleData.latestTelemetry.powerKW,
                    socPct: vehicleData.latestTelemetry.stateOfChargePct,
                    isPresented: $showHUDMode
                )
            }
            #else
            .sheet(isPresented: $showHUDMode) {
                HUDModeView(
                    speedKmH: vehicleData.latestTelemetry.speedKmH,
                    powerKW: vehicleData.latestTelemetry.powerKW,
                    socPct: vehicleData.latestTelemetry.stateOfChargePct,
                    isPresented: $showHUDMode
                )
            }
            #endif
            .sheet(isPresented: $showDemoControls) {
                if let mockAdapter = vehicleData.obdConnection as? MockOBDAdapter {
                    DemoControlSheet(simulationEngine: mockAdapter.simulationEngine)
                }
            }
            .sheet(isPresented: $showCustomization) {
                DashboardCustomizationSheet(layout: $layout, profile: vehicleData.selectedProfile)
            }
        }
    }
}
