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
                                Text(vehicleData.isDemoMode ? "DEMO MODE (\(vehicleData.vehicleName))" : (vehicleData.connectionState.isConnected ? "CONNECTED (\(vehicleData.vehicleName))" : "DISCONNECTED (OBD-II Scanner)"))
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

                        if vehicleData.isCalibrating {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.85)
                                    .tint(Theme.electricCyan)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Calibrating live telemetry metrics (\(Int(vehicleData.calibrationProgress * 100))%)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.electricCyan)
                                    Text("Verifying supported vehicle sensors...")
                                        .font(.caption2)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Theme.cardBackground)
                            .cornerRadius(10)
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
                                        .foregroundColor(Theme.onAccent)
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
                        if layout.widgets.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 40))
                                    .foregroundColor(Theme.textSecondary)
                                Text("No Widgets Yet")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.textPrimary)
                                Text("Tap Edit, then Add Widget to build your dashboard.")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        isEditMode = true
                                    }
                                    showAddWidgetSheet = true
                                } label: {
                                    Label("Add Widget", systemImage: "plus.circle.fill")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.onAccent)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Theme.electricCyan)
                                        .cornerRadius(10)
                                }
                                .padding(.top, 4)
                            }
                            .padding(30)
                            .frame(maxWidth: .infinity)
                            .glassCard()
                            .padding(.horizontal)
                        }

                        ForEach(packDashboardWidgetsIntoRows(layout.widgets), id: \.first!.id) { row in
                            HStack(spacing: 12) {
                                ForEach(row) { widget in
                                    WidgetTileWrapper(
                                        widget: widget,
                                        isEditMode: isEditMode,
                                        snapshot: vehicleData.latestTelemetry,
                                        profile: vehicleData.selectedProfile,
                                        supportedMetrics: vehicleData.supportedMetrics,
                                        liveMetrics: vehicleData.liveMetrics,
                                        telemetryHistory: widget.kind.isChart ? telemetryHistory : [],
                                        isConnected: vehicleData.isDemoMode || vehicleData.connectionState.isConnected,
                                        isDemoMode: vehicleData.isDemoMode,
                                        estimatedFullRangeKm: vehicleData.estimatedFullRangeKm,
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
                                    tripTracker.startTrip(startSoc: vehicleData.latestTelemetry.stateOfChargePct, vehicleName: vehicleData.vehicleName)
                                }
                            } label: {
                                Text(tripTracker.isRecordingTrip ? "Stop Trip" : "Start Trip")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(tripTracker.isRecordingTrip ? Theme.criticalRed : Theme.electricCyan)
                                    .foregroundColor(Theme.onAccent)
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
            }
            .onReceive(vehicleData.$liveMetrics) { _ in
                telemetryHistory.removeAll()
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
                DashboardCustomizationSheet(layout: $layout, supportedMetrics: vehicleData.supportedMetrics)
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
    let supportedMetrics: Set<TelemetryMetric>
    let liveMetrics: Set<TelemetryMetric>
    let telemetryHistory: [TelemetrySnapshot]
    let isConnected: Bool
    let isDemoMode: Bool
    let estimatedFullRangeKm: Double?
    let onDelete: () -> Void
    let onDecreaseSize: () -> Void
    let onIncreaseSize: () -> Void
    let onLongPress: () -> Void

    @State private var isWiggling = false
    // Picked once per edit-mode entry (not recomputed every body evaluation) so the wiggle
    // animation has a stable target angle instead of jittering on every telemetry tick.
    @State private var wiggleAngle = Double.random(in: -1.2...1.2)

    var body: some View {
        ZStack(alignment: .topLeading) {
            DashboardWidgetTile(
                config: widget,
                snapshot: snapshot,
                profile: profile,
                supportedMetrics: supportedMetrics,
                liveMetrics: liveMetrics,
                telemetryHistory: telemetryHistory,
                isConnected: isConnected,
                isDemoMode: isDemoMode,
                estimatedFullRangeKm: estimatedFullRangeKm
            )
            .rotationEffect(.degrees(isEditMode && isWiggling ? wiggleAngle : 0))
            .animation(
                isEditMode ? Animation.easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default,
                value: isWiggling
            )
            .onAppear {
                if isEditMode {
                    wiggleAngle = Double.random(in: -1.2...1.2)
                    isWiggling = true
                }
            }
            .onChange(of: isEditMode) { _, newValue in
                if newValue {
                    wiggleAngle = Double.random(in: -1.2...1.2)
                }
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
                        .foregroundColor(Theme.criticalRed)
                        .background(Circle().fill(Theme.textPrimary))
                }
                .offset(x: -8, y: -8)
                .accessibilityLabel("Delete widget")

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
                        .accessibilityLabel("Decrease widget size")

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
                        .accessibilityLabel("Increase widget size")
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
