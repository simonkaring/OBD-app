#if canImport(CarPlay)
import Foundation
import CarPlay
import Combine

public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    public var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()

    private var socButton: CPGridButton?
    private var powerButton: CPGridButton?
    private var speedButton: CPGridButton?
    private var healthButton: CPGridButton?

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        setupCarPlayDashboard()
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func setupCarPlayDashboard() {
        let batteryImg = UIImage(systemName: "bolt.batteryblock.fill") ?? UIImage()
        let powerImg = UIImage(systemName: "gauge.with.needle.fill") ?? UIImage()
        let speedImg = UIImage(systemName: "speedometer") ?? UIImage()
        let healthImg = UIImage(systemName: "checkmark.shield.fill") ?? UIImage()

        socButton = CPGridButton(titleVariants: ["SOC: 78%", "Battery"], image: batteryImg) { _ in }
        powerButton = CPGridButton(titleVariants: ["Power: 0 kW", "Live kW"], image: powerImg) { _ in }
        speedButton = CPGridButton(titleVariants: ["Speed: 0 km/h", "Speed"], image: speedImg) { _ in }
        healthButton = CPGridButton(titleVariants: ["Health: OK", "Diagnostics"], image: healthImg) { _ in }

        let grid = CPGridTemplate(
            title: "VoltLink EQA",
            gridButtons: [socButton!, powerButton!, speedButton!, healthButton!]
        )

        interfaceController?.setRootTemplate(grid, animated: true)
    }

    public func updateTelemetry(telemetry: TelemetrySnapshot) {
        let socStr = String(format: "SOC: %.0f%%", telemetry.stateOfChargePct)
        let powerStr = String(format: "Power: %.1f kW", telemetry.powerKW)
        let speedStr = String(format: "Speed: %.0f km/h", telemetry.speedKmH)

        socButton = CPGridButton(titleVariants: [socStr, "Battery"], image: UIImage(systemName: "bolt.batteryblock.fill") ?? UIImage()) { _ in }
        powerButton = CPGridButton(titleVariants: [powerStr, "Live kW"], image: UIImage(systemName: "gauge.with.needle.fill") ?? UIImage()) { _ in }
        speedButton = CPGridButton(titleVariants: [speedStr, "Speed"], image: UIImage(systemName: "speedometer") ?? UIImage()) { _ in }

        if let soc = socButton, let pow = powerButton, let spd = speedButton, let hlth = healthButton {
            let updatedGrid = CPGridTemplate(title: "VoltLink EQA", gridButtons: [soc, pow, spd, hlth])
            interfaceController?.setRootTemplate(updatedGrid, animated: false)
        }
    }
}
#endif

