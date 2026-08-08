import SwiftUI

public struct DashboardView: View {
    @ObservedObject public var vehicleData: VehicleDataManager
    @ObservedObject public var tripTracker: TripTrackingManager

    @State private var telemetryHistory: [TelemetrySnapshot] = []
    @State private var showHUDMode = false
    @State private var showCustomization = false
    @State private var isEditMode = false
    @State private var showAddWidgetSheet = false
    @State private var draggedWidget: DashboardWidgetConfig?
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
                                    .fill(vehicleData.isDemoMode ? Theme.electricCyan : (vehicleData.connectionState.isConnected ? Theme.regenGreen : Theme.criticalRed))
                                    .frame(width: 10, height: 10)
                                Text(vehicleData.isDemoMode ? "DEMO MODE (\(vehicleData.selectedProfile.vehicleName))" : (vehicleData.connectionState.isConnected ? "CONNECTED (\(vehicleData.selectedProfile.vehicleName))" : "DISCONNECTED (OBD-II Scanner)"))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.textPrimary)
                            }
                            Spacer()

                            if #available(iOS 26.0, macOS 26.0, *) {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        isEditMode.toggle()
                                    }
                                } label: {
                                    Image(systemName: isEditMode ? "checkmark" : "pencil")
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .controlSize(.regular)
                                .buttonSizing(.fitted)
                                .tint(isEditMode ? Theme.regenGreen : nil)
                                .frame(width: 44, height: 44)
                                .accessibilityLabel(isEditMode ? "Done Editing" : "Edit Dashboard")

                                Button {
                                    showHUDMode = true
                                } label: {
                                    Image(systemName: "sunglasses.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .controlSize(.regular)
                                .buttonSizing(.fitted)
                                .frame(width: 44, height: 44)
                                .accessibilityLabel("Heads-Up Display")
                            } else {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        isEditMode.toggle()
                                    }
                                } label: {
                                    Image(systemName: isEditMode ? "checkmark" : "pencil")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(isEditMode ? Theme.regenGreen : Theme.textPrimary)
                                        .frame(width: 36, height: 36)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                .frame(width: 44, height: 44)
                                .accessibilityLabel(isEditMode ? "Done Editing" : "Edit Dashboard")

                                Button {
                                    showHUDMode = true
                                } label: {
                                    Image(systemName: "sunglasses.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)
                                        .frame(width: 36, height: 36)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                .frame(width: 44, height: 44)
                                .accessibilityLabel("Heads-Up Display")
                            }
                        }
                        .padding(.horizontal)

                        if !vehicleData.isDemoMode && !vehicleData.connectionState.isConnected {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(Theme.highPowerAmber)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("OBD SCANNER NOT CONNECTED")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.highPowerAmber)
                                    Text("Telemetry gauges remain blank until connected via Bluetooth in Settings or Demo Mode is enabled.")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(Theme.textSecondary)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Theme.highPowerAmber.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.highPowerAmber.opacity(0.4), lineWidth: 1)
                            )
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        if isEditMode {
                            HStack {
                                Text("Edit Dashboard")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.electricCyan)
                                Spacer()
                                Button {
                                    showAddWidgetSheet = true
                                } label: {
                                    Label("Add Widget", systemImage: "plus.circle.fill")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Theme.electricCyan)
                                        .cornerRadius(8)
                                }
                                Button {
                                    showCustomization = true
                                } label: {
                                    Label("List Edit", systemImage: "list.bullet")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Customizable widget grid with drag-to-reorder and wiggle mode
                        ForEach(Array(packDashboardWidgetsIntoRows(layout.widgets).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 12) {
                                ForEach(row) { widget in
                                    WidgetTileWrapper(
                                        widget: widget,
                                        isEditMode: isEditMode,
                                        snapshot: vehicleData.latestTelemetry,
                                        profile: vehicleData.selectedProfile,
                                        telemetryHistory: telemetryHistory,
                                        onDelete: {
                                            withAnimation {
                                                layout.widgets.removeAll { $0.id == widget.id }
                                            }
                                        },
                                        onDecreaseSize: {
                                            if let index = layout.widgets.firstIndex(where: { $0.id == widget.id }) {
                                                withAnimation {
                                                    layout.widgets[index].size = .medium
                                                }
                                            }
                                        },
                                        onIncreaseSize: {
                                            if let index = layout.widgets.firstIndex(where: { $0.id == widget.id }) {
                                                withAnimation {
                                                    layout.widgets[index].size = .large
                                                }
                                            }
                                        },
                                        onLongPress: {
                                            if !isEditMode {
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                                    isEditMode = true
                                                }
                                            }
                                        }
                                    )
                                    .onDrag {
                                        self.draggedWidget = widget
                                        return NSItemProvider(object: widget.id.uuidString as NSString)
                                    }
                                    .onDrop(of: [.text], delegate: WidgetDropDelegate(item: widget, layout: $layout, draggedItem: $draggedWidget))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: widget.size.height)
                                }

                                if row.count == 1 && row[0].size == .medium {
                                    Spacer()
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.horizontal)
                        }

                        // Trip Recording Control Bar
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(tripTracker.isRecordingTrip ? "TRIP RECORDING ACTIVE" : "TRIP READY")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(tripTracker.isRecordingTrip ? Theme.regenGreen : Theme.textSecondary)

                                    if tripTracker.isAutoTripEnabled {
                                        Text("AUTO")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Theme.electricCyan.opacity(0.2))
                                            .foregroundColor(Theme.electricCyan)
                                            .cornerRadius(4)
                                    }
                                }

                                if let remaining = tripTracker.stationarySecondsRemaining, remaining > 0 {
                                    Text(String(format: "Stationary • Auto-stop in %ds", remaining))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(Theme.highPowerAmber)
                                } else {
                                    Text(String(format: "%.1f km logged", tripTracker.currentTrip?.distanceKm ?? 0.0))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(Theme.textPrimary)
                                }
                            }

                            Spacer()

                            Button {
                                if tripTracker.isRecordingTrip {
                                    tripTracker.stopTrip(endSoc: vehicleData.latestTelemetry.stateOfChargePct)
                                } else {
                                    tripTracker.startTrip(startSoc: vehicleData.latestTelemetry.stateOfChargePct, vehicleName: vehicleData.selectedProfile.vehicleName)
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
                tripTracker.processTelemetrySnapshot(snap, vehicleName: vehicleData.selectedProfile.vehicleName)
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
            .sheet(isPresented: $showCustomization) {
                DashboardCustomizationSheet(layout: $layout, profile: vehicleData.selectedProfile)
            }
            .sheet(isPresented: $showAddWidgetSheet) {
                AddDashboardWidgetSheet(profile: vehicleData.selectedProfile) { newWidget in
                    layout.widgets.append(newWidget)
                }
            }
        }
    }
}

private struct WidgetDropDelegate: DropDelegate {
    let item: DashboardWidgetConfig
    @Binding var layout: DashboardLayout
    @Binding var draggedItem: DashboardWidgetConfig?

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem, dragged.id != item.id else { return }
        if let fromIndex = layout.widgets.firstIndex(where: { $0.id == dragged.id }),
           let toIndex = layout.widgets.firstIndex(where: { $0.id == item.id }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                layout.widgets.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }
}

private struct WidgetTileWrapper: View {
    let widget: DashboardWidgetConfig
    let isEditMode: Bool
    let snapshot: TelemetrySnapshot
    let profile: VehicleProfile
    let telemetryHistory: [TelemetrySnapshot]
    let onDelete: () -> Void
    let onDecreaseSize: () -> Void
    let onIncreaseSize: () -> Void
    let onLongPress: () -> Void

    @State private var isWiggling = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            DashboardWidgetTile(
                config: widget,
                snapshot: snapshot,
                profile: profile,
                telemetryHistory: telemetryHistory
            )
            .rotationEffect(.degrees(isEditMode && isWiggling ? Double.random(in: -1.2...1.2) : 0))
            .animation(
                isEditMode ? Animation.easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default,
                value: isWiggling
            )
            .onAppear {
                if isEditMode { isWiggling = true }
            }
            .onChange(of: isEditMode) { _, newValue in
                isWiggling = newValue
            }
            .onLongPressGesture {
                onLongPress()
            }

            if isEditMode {
                // Delete button (Top Left)
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white))
                }
                .offset(x: -8, y: -8)

                // Quick Controls overlay (Bottom Bar in edit mode - Arrows adjust size small <-> medium <-> large)
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: onDecreaseSize) {
                            Image(systemName: "arrow.left.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(widget.size == .medium ? Theme.textSecondary.opacity(0.4) : Theme.electricCyan)
                        }
                        .disabled(widget.size == .medium)

                        Text(widget.size == .medium ? "HALF (MED)" : "FULL (LRG)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.electricCyan.opacity(0.3))
                            .foregroundColor(Theme.electricCyan)
                            .cornerRadius(4)

                        Button(action: onIncreaseSize) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(widget.size == .large ? Theme.textSecondary.opacity(0.4) : Theme.electricCyan)
                        }
                        .disabled(widget.size == .large)
                    }
                    .padding(4)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(8)
                    .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview("Dashboard View") {
    DashboardView(
        vehicleData: VehicleDataManager(),
        tripTracker: TripTrackingManager()
    )
}
