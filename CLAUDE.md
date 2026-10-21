# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

VoltLink — a native Swift iOS + CarPlay app for OBD-II diagnostics and live EV telemetry, built with SwiftUI, CoreBluetooth, CarPlay, ActivityKit, and SwiftData. Targets the **Vgate iCar Pro 2S** BLE adapter and the **Mercedes-Benz EQA 250 (2021)**, with a generic SAE J1979 fallback and a physics-based Demo/Simulation mode.

## Commands

```bash
swift test                                                                       # run unit tests (SPM target VoltLinkEngine)
xcodebuild -scheme VoltLink -destination 'platform=iOS Simulator,name=iPhone 17' # build the iOS app
xcodebuild test -scheme VoltLink -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:VoltLinkUITests                                                  # demo-mode UI smoke test
python3 scratch/make_xcodeproj.py                                                # regenerate project + scheme
swift format lint --strict --recursive --configuration .swift-format \
  Package.swift App CarPlay Core Data Services UI Widgets Tests UITests Tools           # formatting gate
open VoltLink.xcodeproj                                                          # open in Xcode (Cmd+R to run; CarPlay via Simulator I/O > External Displays > CarPlay)
./scratch/repack_ipa.sh                                                          # archive & package build/VoltLink.ipa
```

Always run `swift test` after touching PID decoders, ISO-TP frame parsing, or SwiftData models.

The codebase builds two ways: the `Package.swift` SPM target `VoltLinkEngine` (used by `swift test`, macOS-buildable) and the `VoltLink.xcodeproj` Xcode target (used for the actual iOS/CarPlay app and simulator runs). Code under `App/`, `CarPlay`, `Core`, `Data/Models`, `Data/Repositories`, `Services`, `UI`, `Widgets` is shared between both — keep iOS-only frameworks (`CarPlay`, `ActivityKit`) behind `#if canImport(CarPlay)` / `#if os(iOS)` guards so SPM tests keep compiling on macOS.

`scratch/make_xcodeproj.py` is the source of truth for the `.xcodeproj`: it writes the app target, the `VoltLinkUITests` target, and the shared scheme. Regenerate it after adding files or targets instead of hand-editing `project.pbxproj`. Both SPM and Xcode builds use Swift 6 language mode; keep concurrency checks enabled.

CarPlay needs Apple to grant `com.apple.developer.carplay-driving-task`. `App/Info.plist` declares the scene and `App/VoltLink.entitlements` requests the entitlement, but a provisioning profile without it cannot install on device (Simulator is unaffected).

## Knowledge Bundle (OKF)

`knowledge/` is an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/open-knowledge-format) v0.2 bundle (markdown + YAML frontmatter) serving as the repo reference for humans and agents. Architecture concepts are hand-authored; vehicle profiles, telemetry metrics, curated DTCs, and all `index.md` files are generated from `VehicleProfileID`, `TelemetryMetric`, and the seed JSON.

After changing profiles/commands/metrics or DTC seed data: `swift run VoltLinkCLI okf export`. Update `knowledge/architecture/*.md` when behavior changes. `swift test` fails on drift (`KnowledgeBundleTests`). Validate with `swift run VoltLinkCLI okf check`.

## Architecture

Data flows one direction: BLE adapter → parser → vehicle profile → manager → SwiftUI view, fanned out to five tabs (`MainTabView` in `App/VoltLinkApp.swift`) plus a CarPlay scene.

- **`Core/Bluetooth/BluetoothManager`** — `CBCentralManager`-based connection, conforms to `OBDConnectionProtocol` (`Core/OBD/OBDConnectionProtocol.swift`). Scans for peripherals advertising names containing "Vlink"/"iCar"/"OBD", writes ELM327 AT/OBD commands terminated with `\r`, buffers notify responses until a `>` prompt appears.
- **`Core/Demo/MockOBDAdapter`** — implements the same `OBDConnectionProtocol`, backed by `MockDrivingSimulation` (physics-based speed/power/SOC simulation). `VehicleDataManager` swaps between real BLE and this mock via `toggleDemoMode`; first run starts on the vehicle picker, which offers demo mode.
- **`Core/OBD/ISO15765Parser`** — reassembles multi-line ISO-TP CAN frames (single/first/consecutive frame types) from raw ELM327 text into one hex payload string. Vehicle profiles parse against this reassembled hex, not raw adapter output.
- **`Core/Vehicles/VehicleProfile`** protocol — one profile per vehicle (`MercedesEQA250Profile` using UDS Service `0x22` ReadDataByIdentifier over CAN headers `7E4`/BMS and `7E0`/Powertrain; `GenericOBD2Profile` for SAE J1979 Mode 01). Each profile owns its `initializationCommands`, `pollingCommands`, and `parseResponse(command:rawResponse:)` → `TelemetryUpdate`.
- **`Services/VehicleDataManager`** — `@MainActor` `@Observable` facade. `Services/TelemetryPollingLoop` polls `selectedProfile.pollingCommands` round-robin in a cancellable `Task`; the manager merges each `TelemetryUpdate` into `latestTelemetry`/`liveMetrics` and emits `telemetryPublisher` for non-UI consumers. Plausibility, SoC-slope charging estimation, and SOC reference persistence live in `Core/Telemetry` collaborators.
- **`Services/DTCScannerService`** — Mode 03 (read DTCs) / Mode 04 (clear DTCs), decodes 2-byte DTC pairs into `P`/`C`/`B`/`U` codes, looked up against `Data/Repositories/DTCLocalDatabase` (backed by bundled `Data/Seed/dtc_definitions.json`).
- **`Services/TripTrackingManager`** + **`Core/Location/TripLocationManager`** — CoreLocation-based trip recording; background location updates are only enabled after `.authorizedAlways` is confirmed via `locationManagerDidChangeAuthorization` (not requested proactively — see recent fix in git log).
- **`App/AppEnvironment`** — composition root holding `VehicleDataManager`, `TripTrackingManager`, `ChargingTrackingManager`, and `DTCScannerService`. `vehicleData` and `tripTracker` are injected with `.environment(...)` (iOS 17 Observation); the remaining observable managers use `@EnvironmentObject`.
- **`CarPlay/CarPlaySceneDelegate`** — separate `CPTemplateApplicationSceneDelegate` scene rendering a `CPGridTemplate` glanceable dashboard (SOC%, power kW, speed, health) from the same `VehicleDataManager`.
- **`Widgets/`** — WidgetKit extension: `VoltLinkStatusWidget` (Home Screen + accessory families) and `VoltLinkLiveActivityWidget` (Lock Screen + Dynamic Island). The app writes a compact `SharedTelemetrySnapshot` into the `group.com.simonkaring.voltlink` app group (`Core/Sharing/SharedTelemetryStore.swift`); the extension never opens SwiftData or CoreBluetooth. `Services/LiveActivityCoordinator` owns the single activity and is updated from `AppEnvironment`'s telemetry subscription.
- **`Core/Units/UnitPreferences`** — metric/imperial distance, °C/°F, and kW/hp display conversions. Telemetry and exports stay SI; only presentation converts. Injected as a shared `@Observable` singleton read from views.
- **`Core/Notifications/NotificationService`** — opt-in local notifications for charging finished, adapter loss during a trip, and fault codes found. Permission is requested only when the matching Settings toggle is enabled.
- **`Services/AppIntents.swift`** — App Intents/App Shortcuts for charge status, start trip, and stop trip.
- Persistence is SwiftData: `TripModel`, `TelemetryPointModel`, `ChargingSessionModel`, `ChargingSampleModel`, `SavedDTCModel`, registered in `VoltLinkSchemaV2` and opened through `VoltLinkCurrentSchema` in `App/AppEnvironment`. Additive changes rely on SwiftData's inferred lightweight migration; do not add a `SchemaMigrationPlan` whose versions share model classes (Core Data aborts instead of migrating). A destructive change needs distinct legacy model copies plus a real migration stage.
- The app group (`group.com.simonkaring.voltlink`) must be enabled for both `com.simonkaring.voltlink` and `com.simonkaring.voltlink.widgets` in the developer portal. Without it the widget shows its placeholder; the app still works.
- Charging sessions store a throttled power-vs-SOC curve (`ChargingSampleModel`, one point per 1% SOC or 60 s) rendered in `ChargingSessionDetailView`.
- Trip GPX/CSV and charging CSV export live in `Core/Export/TripExport.swift` and are exposed through `ShareLink` on the detail screens.
- `App/PrivacyInfo.xcprivacy` must stay in the app target; `App/Localizable.xcstrings` is the source string catalog.

- Swift 6 language mode is enforced (`swiftLanguageModes: [.v6]`, `SWIFT_VERSION = 6.0`). `OBDConnectionProtocol`/`OBDConnectionDelegate` and the managers are `@MainActor`; `VehicleProfile` types stay `Sendable`.
- Design tokens live in `UI/DesignSystem/Theme.swift` (dark slate background, electric cyan accent, emerald green for regen, amber for high power draw, crimson for faults) — reuse these rather than hardcoding colors, in keeping with the glassmorphism (`.ultraThinMaterial`) aesthetic described in `.gemini/rules.md`.

## Git & Commit Conventions

Always use **Conventional Commits** syntax with explicit scope and a detailed commit message body.

### Commit Format:
```
<type>(<scope>): <short summary in imperative mood>

<detailed description of changes, root causes fixed, and affected files/modules>
```

### Types & Scopes:
- **Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`
- **Scopes**: `telemetry`, `obd`, `bluetooth`, `carplay`, `ui`, `location`, `diagnostics`, `models`, `xcodeproj`, `deps`

### Example:
```git
feat(telemetry): implement ISO-TP multi-frame CAN buffer reassembly

- Add ISO15765Parser to decode Single, First, and Consecutive CAN frames
- Handle flow control frame responses during high-frequency ELM327 polling
- Unit test multi-frame payload reassembly in OBDParserTests
```
