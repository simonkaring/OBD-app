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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(vehicleData: VehicleDataManager, tripTracker: TripTrackingManager) {
        self.vehicleData = vehicleData
        self.tripTracker = tripTracker
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        // Connection Header Bar
                        HStack(spacing: 8) {
                            Circle()
                                .fill(vehicleData.isDemoMode ? Theme.electricCyan : (vehicleData.connectionState.isConnected ? Theme.regenGreen : Theme.criticalRed))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(vehicleData.isDemoMode ? "Demo mode" : (vehicleData.connectionState.isConnected ? "Connected" : "Disconnected"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Theme.textPrimary)
                                Text(vehicleData.vehicleName)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        if vehicleData.isCalibrating {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.85)
                                    .tint(Theme.electricCyan)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Calibrating live telemetry metrics (\(Int(vehicleData.calibrationProgress * 100))%)")
                                        .font(.subheadline.weight(.semibold))
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
                                    .font(.headline)
                                    .foregroundColor(Theme.electricCyan)
                                Spacer()
                                Button {
                                    showAddWidgetSheet = true
                                } label: {
                                    Label("Add Widget", systemImage: "plus.circle.fill")
                                        .font(.subheadline.weight(.semibold))
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
                                        .font(.subheadline)
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
                                    .font(.headline)
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
                                        .font(.subheadline.weight(.semibold))
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

                        ForEach(dynamicTypeSize.isAccessibilitySize ? layout.widgets.map { [$0] } : packDashboardWidgetsIntoRows(layout.widgets), id: \.first!.id) { row in
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(row) { widget in
                                    WidgetTileWrapper(
                                        widget: widget,
                                        isEditMode: isEditMode,
                                        snapshot: tripTracker.telemetryForDisplay(vehicleData.displayedTelemetry),
                                        profile: vehicleData.selectedProfile,
                                        supportedMetrics: vehicleData.supportedMetrics,
                                        liveMetrics: vehicleData.liveMetrics,
                                        telemetryHistory: widget.kind.isChart ? telemetryHistory.map(vehicleData.telemetryForDisplay) : [],
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
                                    .frame(minHeight: widget.preferredHeight)
                                }

                                if row.count == 1 && row[0].size == .medium && !dynamicTypeSize.isAccessibilitySize {
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
                                    Text(tripTracker.isRecordingTrip ? "Recording trip" : "Ready to record")
                                        .font(.subheadline)
                                        .foregroundColor(tripTracker.isRecordingTrip ? Theme.regenGreen : Theme.textSecondary)

                                    if tripTracker.isAutoTripEnabled {
                                        Text("Auto")
                                            .font(.caption)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Theme.electricCyan.opacity(0.2))
                                            .foregroundColor(Theme.electricCyan)
                                            .cornerRadius(4)
                                    }
                                }

                                if let remaining = tripTracker.stationarySecondsRemaining, remaining > 0 {
                                    Text(String(format: "Stationary • Auto-stop in %ds", remaining))
                                        .font(.subheadline)
                                        .foregroundColor(Theme.highPowerAmber)
                                } else {
                                    Text(String(format: "%.1f km logged", tripTracker.currentTrip?.distanceKm ?? 0.0))
                                        .font(.headline)
                                        .monospacedDigit()
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
                                    .font(.subheadline.weight(.semibold))
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
            .navigationTitle("Telemetry")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(isEditMode ? "Done" : "Edit", systemImage: isEditMode ? "checkmark" : "pencil") {
                        withAnimation { isEditMode.toggle() }
                    }
                    .accessibilityLabel(isEditMode ? "Done Editing" : "Edit Dashboard")
                    Button("Heads-Up Display", systemImage: "sunglasses") {
                        showHUDMode = true
                    }
                }
            }
            .onReceive(vehicleData.$latestTelemetry) { snap in
                telemetryHistory.append(tripTracker.telemetryForDisplay(snap))
                if telemetryHistory.count > 50 {
                    telemetryHistory.removeFirst()
                }
            }
            .onChange(of: vehicleData.selectedVehicle.id) { _, _ in
                telemetryHistory.removeAll()
            }
            .onChange(of: vehicleData.selectedModelYear) { _, _ in
                telemetryHistory.removeAll()
            }
            .onChange(of: vehicleData.isDemoMode) { _, _ in
                telemetryHistory.removeAll()
            }
            .onChange(of: vehicleData.connectionState.isConnected) { _, _ in
                telemetryHistory.removeAll()
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showHUDMode) {
                HUDModeView(
                    speedKmH: vehicleData.latestTelemetry.speedKmH,
                    powerKW: vehicleData.latestTelemetry.powerKW,
                    socPct: vehicleData.isDemoMode || vehicleData.liveMetrics.contains(.soc) ? vehicleData.displayedTelemetry.stateOfChargePct : nil,
                    isPresented: $showHUDMode
                )
            }
            #else
            .sheet(isPresented: $showHUDMode) {
                HUDModeView(
                    speedKmH: vehicleData.latestTelemetry.speedKmH,
                    powerKW: vehicleData.latestTelemetry.powerKW,
                    socPct: vehicleData.isDemoMode || vehicleData.liveMetrics.contains(.soc) ? vehicleData.displayedTelemetry.stateOfChargePct : nil,
                    isPresented: $showHUDMode
                )
            }
            #endif
            .sheet(isPresented: $showCustomization) {
                DashboardCustomizationSheet(layout: $layout, supportedMetrics: vehicleData.supportedMetrics)
            }
            .sheet(isPresented: $showAddWidgetSheet) {
                AddDashboardWidgetSheet(supportedMetrics: vehicleData.supportedMetrics) { newWidget in
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

                        Text(widget.size == .medium ? "Half" : "Full")
                            .font(.caption)
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
