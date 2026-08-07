#if canImport(CarPlay)
import Foundation
import CarPlay
import Combine

public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    public var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        rebuildGrid()

        AppEnvironment.shared.vehicleData.$latestTelemetry
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildGrid() }
            .store(in: &cancellables)
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        self.interfaceController = nil
    }

    private func rebuildGrid() {
        let vehicleData = AppEnvironment.shared.vehicleData
        let dtcService = AppEnvironment.shared.dtcService
        let profile = vehicleData.selectedProfile
        let snapshot = vehicleData.latestTelemetry
        let layout = CarPlayLayout.load()

        let buttons: [CPGridButton] = layout.tiles.compactMap { tile in
            gridButton(for: tile, profile: profile, snapshot: snapshot, dtcService: dtcService)
        }

        guard !buttons.isEmpty else { return }

        let grid = CPGridTemplate(title: profile.vehicleName, gridButtons: buttons)
        interfaceController?.setRootTemplate(grid, animated: false)
    }

    private func gridButton(for tile: CarPlayTileKind, profile: VehicleProfile, snapshot: TelemetrySnapshot, dtcService: DTCScannerService) -> CPGridButton? {
        switch tile {
        case .metric(let metric):
            guard profile.supportedMetrics.contains(metric) else { return nil }
            let value = metric.value(in: snapshot)
            let valueStr = String(format: "%.1f %@", value, metric.unitSymbol)
            let image = UIImage(systemName: metric.sfSymbolName) ?? UIImage()
            return CPGridButton(titleVariants: [valueStr, metric.displayName], image: image) { _ in }

        case .health:
            let image = UIImage(systemName: "checkmark.shield.fill") ?? UIImage()
            let statusStr: String
            if dtcService.lastScanDate == nil {
                statusStr = "Health: --"
            } else if dtcService.scannedCodes.isEmpty {
                statusStr = "Health: OK"
            } else {
                statusStr = "Health: \(dtcService.scannedCodes.count) Faults"
            }
            return CPGridButton(titleVariants: [statusStr, "Diagnostics"], image: image) { _ in }
        }
    }
}
#endif
