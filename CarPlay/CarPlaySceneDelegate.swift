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
        cachedLayout = CarPlayLayout.load()
        rebuildInterface()

        // All telemetry/validity and diagnostic changes share one refresh budget.
        let env = AppEnvironment.shared
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

    private func rebuildInterface() {
        let vehicleData = AppEnvironment.shared.vehicleData
        let dtcService = AppEnvironment.shared.dtcService
        let snapshot = vehicleData.latestTelemetry
        let layout = cachedLayout

        // 1. Driving Mode Template
        let buttons: [CPGridButton] = layout.tiles.compactMap { tile in
            gridButton(for: tile, supportedMetrics: vehicleData.supportedMetrics, liveMetrics: vehicleData.liveMetrics, snapshot: snapshot, dtcService: dtcService, isDemoMode: vehicleData.isDemoMode)
        }
        if let drivingTemplate, let chargingTemplate, let diagnosticsTemplate {
            drivingTemplate.updateGridButtons(buttons)
            chargingTemplate.items = buildChargingItems(snapshot: snapshot)
            diagnosticsTemplate.items = buildHealthItems(dtcService: dtcService)
            return
        }
        let drivingTemplate = CPGridTemplate(title: "", gridButtons: buttons)
        drivingTemplate.tabTitle = "Driving"
        drivingTemplate.tabImage = UIImage(systemName: "gauge.with.dots.needle.bottom.50percent")

        // 2. Charging Mode Template
        let chargingItems = buildChargingItems(snapshot: snapshot)
        let chargingTemplate = CPInformationTemplate(title: "", layout: .twoColumn, items: chargingItems, actions: [])
        chargingTemplate.tabTitle = "Charging"
        chargingTemplate.tabImage = UIImage(systemName: "bolt.batteryblock")

        // 3. Diagnostics Mode Template
        let healthItems = buildHealthItems(dtcService: dtcService)
        let diagnosticsTemplate = CPInformationTemplate(title: "", layout: .twoColumn, items: healthItems, actions: [])
        diagnosticsTemplate.tabTitle = "Diagnostics"
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
        let hasSOC = vehicleData.isDemoMode || vehicleData.liveMetrics.contains(.soc)
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
        let timeMin: String
        if hasSOC && isCharging {
            let neededKWh = (remainingPct / 100.0) * vehicleData.usableBatteryCapacityKWh
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
            let image = cachedDialImage(for: metric, value: value)
            let valueStr = isDemoMode || liveMetrics.contains(metric) ? String(format: "%.1f %@", value, metric.unitSymbol) : "-- \(metric.unitSymbol)"
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
    private func renderDialImage(for metric: TelemetryMetric, value: Double) -> UIImage {
        let range = metric.defaultRange
        let mode: DialMode = range.lowerBound < 0 ? .bidirectional(negativeMax: abs(range.lowerBound)) : .unidirectional
        let dialView = MetricDialView(value: value, range: range, mode: mode, unit: metric.unitSymbol, label: metric.displayName)

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
