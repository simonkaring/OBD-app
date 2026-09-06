#if canImport(CarPlay)
import Foundation
import CarPlay
import Combine
import SwiftUI

public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    public var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()
    private var tabBarTemplate: CPTabBarTemplate?

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

        AppEnvironment.shared.vehicleData.$latestTelemetry
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.rebuildInterface() }
            .store(in: &cancellables)

        AppEnvironment.shared.vehicleData.$liveMetrics
            .receive(on: DispatchQueue.main)
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

        if let existing = tabBarTemplate {
            existing.updateTemplates([drivingTemplate, chargingTemplate, diagnosticsTemplate])
        } else {
            let tabBar = CPTabBarTemplate(templates: [drivingTemplate, chargingTemplate, diagnosticsTemplate])
            self.tabBarTemplate = tabBar
            interfaceController?.setRootTemplate(tabBar, animated: false)
        }
    }

    private func buildChargingItems(snapshot: TelemetrySnapshot) -> [CPInformationItem] {
        let isCharging = snapshot.isCharging || snapshot.chargePowerKW > 0.5
        let powerKW = snapshot.chargePowerKW > 0 ? snapshot.chargePowerKW : abs(snapshot.powerKW)
        let powerStr = String(format: "%.1f kW", powerKW)
        let socStr = String(format: "%.1f%%", snapshot.stateOfChargePct)
        
        let remainingPct = max(0.0, 80.0 - snapshot.stateOfChargePct)
        let timeMin: String
        if powerKW > 1.0 {
            let batteryCapacityKWh = AppEnvironment.shared.vehicleData.usableBatteryCapacityKWh
            let neededKWh = (remainingPct / 100.0) * batteryCapacityKWh
            let hours = neededKWh / powerKW
            let mins = Int(ceil(hours * 60.0))
            timeMin = "\(mins) min to 80%"
        } else {
            timeMin = "-- min"
        }

        let hasBatteryTemperature = AppEnvironment.shared.vehicleData.liveMetrics.contains(.batteryTemp)
        let tempStr = hasBatteryTemperature ? String(format: "%.1f °C", snapshot.batteryTempC) : "Unavailable"

        return [
            CPInformationItem(title: "STATUS", detail: isCharging ? "CHARGING ACTIVE" : "NOT CHARGING"),
            CPInformationItem(title: "CHARGE RATE", detail: powerStr),
            CPInformationItem(title: "BATTERY SOC", detail: socStr),
            CPInformationItem(title: "EST. TIME TO 80%", detail: timeMin),
            CPInformationItem(title: "BATTERY TEMP", detail: tempStr)
        ]
    }

    private func buildHealthItems(dtcService: DTCScannerService) -> [CPInformationItem] {
        let statusStr: String
        if dtcService.lastScanDate == nil {
            statusStr = "Scan Not Performed"
        } else if dtcService.scannedCodes.isEmpty {
            statusStr = "OK - No Fault Codes"
        } else {
            statusStr = "\(dtcService.scannedCodes.count) Fault Codes"
        }
        
        let lastScanStr = dtcService.lastScanDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
        
        return [
            CPInformationItem(title: "SYSTEM HEALTH", detail: statusStr),
            CPInformationItem(title: "LAST SCAN", detail: lastScanStr),
            CPInformationItem(title: "DIAGNOSTIC FAULTS", detail: "\(dtcService.scannedCodes.count) DTCs")
        ]
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
            let statusStr: String
            if dtcService.lastScanDate == nil {
                statusStr = "Health: --"
            } else if dtcService.scannedCodes.isEmpty {
                statusStr = "Health: OK"
            } else {
                statusStr = "Health: \(dtcService.scannedCodes.count) Faults"
            }
            let image = renderHealthImage(scannedCodesCount: dtcService.scannedCodes.count, isScanned: dtcService.lastScanDate != nil)
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
