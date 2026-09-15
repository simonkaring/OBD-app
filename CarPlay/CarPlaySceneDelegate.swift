#if canImport(CarPlay)
import Foundation
import CarPlay
import Combine
import SwiftUI

public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    public var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()
    private var tabBarTemplate: CPTabBarTemplate?
    private var drivingTemplate: CPGridTemplate?
    private var chargingTemplate: CPInformationTemplate?
    private var diagnosticsTemplate: CPInformationTemplate?
    private var healthImageCache: (status: String, image: UIImage)?

    /// `CarPlayLayout.load()` decodes JSON out of `UserDefaults` — cache it and only reload
    /// when the tile selection actually changes (edited on the phone side), not on every
    /// telemetry tick (rebuildInterface can run up to 5x/sec).
    private var cachedLayout = CarPlayLayout.load()
    /// Last rendered dial image per metric, keyed with the value it was rendered at, so a
    /// telemetry tick that doesn't meaningfully change a metric skips the (expensive)
    /// `ImageRenderer` pass for that tile.
    private var dialImageCache: [TelemetryMetric: (value: Double, image: UIImage)] = [:]

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        let env = AppEnvironment.shared

        cachedLayout = CarPlayLayout.load()
        // rebuildInterface() itself gates on hasSelectedVehicle/isDemoMode and shows the
        // first-run template when neither is true yet.
        rebuildInterface()

        // All telemetry/validity/diagnostic changes AND vehicle-selection/demo-mode changes
        // share one refresh budget — vehicleData.objectWillChange already fires for those,
        // so first-run -> real UI transitions rebuild through this same subscription.
        Publishers.MergeMany([env.vehicleData.objectWillChange.eraseToAnyPublisher(),
                               env.dtcService.objectWillChange.eraseToAnyPublisher(),
                               env.tripTracker.objectWillChange.eraseToAnyPublisher(),
                               env.chargingTracker.objectWillChange.eraseToAnyPublisher()])
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.rebuildInterface() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let reloaded = CarPlayLayout.load()
                if reloaded != self.cachedLayout {
                    self.cachedLayout = reloaded
                    self.dialImageCache.removeAll()
                    self.rebuildInterface()
                }
            }
            .store(in: &cancellables)
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        self.interfaceController = nil
        self.tabBarTemplate = nil
        self.drivingTemplate = nil
        self.chargingTemplate = nil
        self.diagnosticsTemplate = nil
        self.healthImageCache = nil
        self.dialImageCache.removeAll()
    }

    private func showFirstRunTemplate(interfaceController: CPInterfaceController) {
        let message = CPInformationTemplate(
            title: "Select Your Vehicle",
            layout: .twoColumn,
            items: [
                CPInformationItem(title: "First Time Setup", detail: "Please select your vehicle on your iPhone to continue."),
                CPInformationItem(title: "Or Try Demo", detail: "Tap 'Start Demo Mode' on your iPhone to simulate a vehicle without an OBD adapter.")
            ],
            actions: []
        )
        interfaceController.setRootTemplate(message, animated: false, completion: nil)
    }

    /// Drops any built templates so a later transition back to the real UI rebuilds fresh
    /// rather than reusing stale grid/charging/diagnostics content.
    private func clearCachedTemplates() {
        tabBarTemplate = nil
        drivingTemplate = nil
        chargingTemplate = nil
        diagnosticsTemplate = nil
        healthImageCache = nil
        dialImageCache.removeAll()
    }

    private func rebuildInterface() {
        let vehicleData = AppEnvironment.shared.vehicleData

        // Gate here (not in didConnect) so toggling demo mode off, or first-run selection
        // completing, both flow through the same rebuild without dropping subscriptions.
        guard vehicleData.hasSelectedVehicle || vehicleData.isDemoMode else {
            clearCachedTemplates()
            if let interfaceController {
                showFirstRunTemplate(interfaceController: interfaceController)
            }
            return
        }

        let dtcService = AppEnvironment.shared.dtcService
        let snapshot = AppEnvironment.shared.tripTracker.telemetryForDisplay(vehicleData.displayedTelemetry)
        let layout = cachedLayout
        let demoSuffix = vehicleData.isDemoMode ? " (Demo)" : ""

        // 1. Driving Mode Template
        let buttons: [CPGridButton] = layout.tiles.compactMap { tile in
            gridButton(for: tile, supportedMetrics: vehicleData.supportedMetrics, liveMetrics: vehicleData.liveMetrics, snapshot: snapshot, dtcService: dtcService, isDemoMode: vehicleData.isDemoMode)
        }
        if let drivingTemplate, let chargingTemplate, let diagnosticsTemplate {
            drivingTemplate.updateGridButtons(buttons)
            drivingTemplate.tabTitle = "Driving" + demoSuffix
            chargingTemplate.items = buildChargingItems(snapshot: snapshot)
            chargingTemplate.tabTitle = "Charging" + demoSuffix
            diagnosticsTemplate.items = buildHealthItems(dtcService: dtcService)
            diagnosticsTemplate.tabTitle = "Diagnostics" + demoSuffix
            return
        }
        let drivingTemplate = CPGridTemplate(title: "", gridButtons: buttons)
        drivingTemplate.tabTitle = "Driving" + demoSuffix
        drivingTemplate.tabImage = UIImage(systemName: "gauge.with.dots.needle.bottom.50percent")

        // 2. Charging Mode Template
        let chargingItems = buildChargingItems(snapshot: snapshot)
        let chargingTemplate = CPInformationTemplate(title: "", layout: .twoColumn, items: chargingItems, actions: [])
        chargingTemplate.tabTitle = "Charging" + demoSuffix
        chargingTemplate.tabImage = UIImage(systemName: "bolt.batteryblock")

        // 3. Diagnostics Mode Template
        let healthItems = buildHealthItems(dtcService: dtcService)
        let diagnosticsTemplate = CPInformationTemplate(title: "", layout: .twoColumn, items: healthItems, actions: [])
        diagnosticsTemplate.tabTitle = "Diagnostics" + demoSuffix
        diagnosticsTemplate.tabImage = UIImage(systemName: "stethoscope")

        self.drivingTemplate = drivingTemplate
        self.chargingTemplate = chargingTemplate
        self.diagnosticsTemplate = diagnosticsTemplate
        let tabBar = CPTabBarTemplate(templates: [drivingTemplate, chargingTemplate, diagnosticsTemplate])
        self.tabBarTemplate = tabBar
        interfaceController?.setRootTemplate(tabBar, animated: false, completion: nil)
    }

    private func buildChargingItems(snapshot: TelemetrySnapshot) -> [CPInformationItem] {
        let vehicleData = AppEnvironment.shared.vehicleData
        let isConnected = vehicleData.isDemoMode || vehicleData.connectionState.isConnected
        // Demo SOC is synthetic and always "fresh"; live SOC must have updated recently,
        // otherwise a stalled connection would keep showing the last known percentage.
        let hasSOC = isConnected && TelemetryMetric.soc.isAvailable(in: snapshot, liveMetrics: vehicleData.liveMetrics, isDemoMode: vehicleData.isDemoMode)
        let hasChargePower = isConnected && vehicleData.hasChargePower
        let isCharging = hasChargePower && (snapshot.isCharging || snapshot.chargePowerKW > 0)
        let powerKW = snapshot.chargePowerKW
        let powerStr = hasChargePower ? String(format: "%.1f kW", powerKW) : "-- kW"
        let socStr = hasSOC ? String(format: "%.1f%%", snapshot.stateOfChargePct) : "--%"

        let statusStr: String
        if !isConnected {
            statusStr = "SCANNER DISCONNECTED"
        } else if !hasChargePower {
            statusStr = "CHARGE DATA UNAVAILABLE"
        } else if !isCharging {
            statusStr = "NOT CHARGING"
        } else {
            statusStr = snapshot.chargePowerSource == .socEstimate ? "CHARGING (ESTIMATED)" : "CHARGING ACTIVE"
        }
        
        let remainingPct = max(0.0, 80.0 - snapshot.stateOfChargePct)
        let capacityKWh = vehicleData.usableBatteryCapacityKWh
        let timeMin: String
        // Generic/unrecognized vehicles report a 0 kWh capacity — can't estimate a time
        // from an unknown pack size, so fall back to "--" instead of a bogus "0 min".
        if hasSOC && isCharging && capacityKWh > 0 {
            let neededKWh = (remainingPct / 100.0) * capacityKWh
            let mins = remainingPct > 0 && powerKW > 0 ? Int(ceil(neededKWh / powerKW * 60.0)) : 0
            timeMin = "\(mins) min to 80%"
        } else {
            timeMin = "-- min"
        }

        let hasBatteryTemperature = vehicleData.isDemoMode || vehicleData.liveMetrics.contains(.batteryTemp)
        let tempStr = isConnected && hasBatteryTemperature ? String(format: "%.1f °C", snapshot.batteryTempC) : "Unavailable"

        return [
            CPInformationItem(title: "STATUS", detail: statusStr),
            CPInformationItem(title: "CHARGE RATE", detail: powerStr),
            CPInformationItem(title: "BATTERY SOC", detail: socStr),
            CPInformationItem(title: "EST. TIME TO 80%", detail: timeMin),
            CPInformationItem(title: "BATTERY TEMP", detail: tempStr)
        ]
    }

    private func buildHealthItems(dtcService: DTCScannerService) -> [CPInformationItem] {
        let statusStr = dtcService.healthSummary
        
        let lastScanStr = dtcService.lastScanDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
        
        var items = [
            CPInformationItem(title: "SYSTEM HEALTH", detail: statusStr),
            CPInformationItem(title: "LAST SCAN", detail: lastScanStr),
            CPInformationItem(title: "DIAGNOSTIC FAULTS", detail: "\(dtcService.scannedCodes.count) DTCs")
        ]
        let env = AppEnvironment.shared
        if let error = env.storageWarning ?? env.tripTracker.persistenceError ?? env.chargingTracker.persistenceError {
            items.append(CPInformationItem(title: "HISTORY STORAGE", detail: error))
        }
        return items
    }

    private func gridButton(for tile: CarPlayTileKind, supportedMetrics: Set<TelemetryMetric>, liveMetrics: Set<TelemetryMetric>, snapshot: TelemetrySnapshot, dtcService: DTCScannerService, isDemoMode: Bool = false) -> CPGridButton? {
        switch tile {
        case .metric(let metric):
            guard isDemoMode || supportedMetrics.contains(metric) else { return nil }
            let value = metric.value(in: snapshot)
            let available = metric.isAvailable(in: snapshot, liveMetrics: liveMetrics, isDemoMode: isDemoMode, at: .now)
            let image = available ? cachedDialImage(for: metric, value: value) : renderDialImage(for: metric, value: 0, isUnavailable: true)
            let valueStr = available ? String(format: "%.1f %@", value, metric.unitSymbol) : "-- \(metric.unitSymbol)"
            return CPGridButton(titleVariants: [metric.displayName.uppercased(), valueStr], image: image) { _ in }

        case .health:
            let statusStr = dtcService.healthSummary
            let image: UIImage
            if let cached = healthImageCache, cached.status == statusStr {
                image = cached.image
            } else {
                image = renderHealthImage(scannedCodesCount: dtcService.scannedCodes.count,
                                          isScanned: dtcService.scanSucceeded && !dtcService.isScanning)
                healthImageCache = (statusStr, image)
            }
            return CPGridButton(titleVariants: ["SYSTEM HEALTH", statusStr], image: image) { _ in }
        }
    }

    /// Reuses the previous render when `value` hasn't moved meaningfully — `ImageRenderer`
    /// is expensive and `rebuildInterface()` can run up to 5x/sec while driving.
    @MainActor
    private func cachedDialImage(for metric: TelemetryMetric, value: Double) -> UIImage {
        if let cached = dialImageCache[metric], abs(cached.value - value) < 0.5 {
            return cached.image
        }
        let image = renderDialImage(for: metric, value: value)
        dialImageCache[metric] = (value, image)
        return image
    }

    @MainActor
    private func renderDialImage(for metric: TelemetryMetric, value: Double, isUnavailable: Bool = false) -> UIImage {
        let range = metric.defaultRange
        let mode: DialMode = range.lowerBound < 0 ? .bidirectional(negativeMax: abs(range.lowerBound)) : .unidirectional
        let dialView = MetricDialView(value: value, range: range, mode: mode, unit: metric.unitSymbol, label: metric.displayName, isUnavailable: isUnavailable)

        let container = dialView
            .padding(4)
            .frame(width: 320, height: 320)
            .background(Color.clear)

        let renderer = ImageRenderer(content: container)
        renderer.scale = 3.0
        return renderer.uiImage ?? UIImage()
    }

    @MainActor
    private func renderHealthImage(scannedCodesCount: Int, isScanned: Bool) -> UIImage {
        let view = ZStack {
            Circle()
                .fill(isScanned ? (scannedCodesCount == 0 ? Theme.regenGreen.opacity(0.2) : Theme.criticalRed.opacity(0.2)) : Color.white.opacity(0.1))
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 130))
                .foregroundColor(isScanned ? (scannedCodesCount == 0 ? Theme.regenGreen : Theme.criticalRed) : Theme.textSecondary)
        }
        .frame(width: 320, height: 320)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0
        return renderer.uiImage ?? UIImage()
    }
}
#endif
