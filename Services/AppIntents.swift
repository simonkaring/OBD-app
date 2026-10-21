#if os(iOS)
import AppIntents
import Foundation

/// "How much charge do I have?" — answers from the last telemetry snapshot.
struct ChargeStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Charge Status"
    static let description = IntentDescription("Reports the vehicle's state of charge and remaining range.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { () -> String in
            let vehicleData = AppEnvironment.shared.vehicleData
            guard vehicleData.hasSelectedVehicle else {
                return "No vehicle is selected in VoltLink yet."
            }
            guard vehicleData.isDemoMode || vehicleData.connectionState.isConnected else {
                return "VoltLink is not connected to the OBD adapter."
            }
            let soc = Int(vehicleData.displayedTelemetry.stateOfChargePct.rounded())
            let rangeText: String
            if let fullRange = vehicleData.estimatedFullRangeKm {
                let remaining = Int((fullRange * vehicleData.displayedTelemetry.stateOfChargePct / 100).rounded())
                rangeText = " and about \(remaining) kilometers of range"
            } else {
                rangeText = ""
            }
            let charging = vehicleData.latestTelemetry.isCharging ? " Charging now." : ""
            return "\(vehicleData.vehicleName) is at \(soc) percent\(rangeText).\(charging)"
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Starts a manual trip recording from Siri or Shortcuts.
struct StartTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Trip"
    static let description = IntentDescription("Starts recording a trip in VoltLink.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { () -> String in
            let environment = AppEnvironment.shared
            guard environment.tripTracker.currentTrip == nil else {
                return "A trip is already being recorded."
            }
            environment.tripTracker.startTrip(
                startSoc: environment.vehicleData.displayedTelemetry.stateOfChargePct,
                vehicleName: environment.vehicleData.vehicleName
            )
            return "Trip recording started."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StopTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Trip"
    static let description = IntentDescription("Stops the current VoltLink trip recording.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { () -> String in
            let environment = AppEnvironment.shared
            guard environment.tripTracker.currentTrip != nil else {
                return "No trip is being recorded."
            }
            let saved = environment.tripTracker.stopTrip(
                endSoc: environment.vehicleData.displayedTelemetry.stateOfChargePct)
            return saved ? "Trip saved." : "The trip could not be saved."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct VoltLinkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ChargeStatusIntent(),
            phrases: [
                "How much charge does \(.applicationName) show?",
                "\(.applicationName) charge status",
            ],
            shortTitle: "Charge Status",
            systemImageName: "bolt.batteryblock"
        )
        AppShortcut(
            intent: StartTripIntent(),
            phrases: ["Start a trip with \(.applicationName)"],
            shortTitle: "Start Trip",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: StopTripIntent(),
            phrases: ["Stop the trip in \(.applicationName)"],
            shortTitle: "Stop Trip",
            systemImageName: "stop.circle"
        )
    }
}
#endif
