# VoltLink Agent Guide

## Project

VoltLink is a native Swift iOS and CarPlay OBD-II diagnostics and live EV
telemetry app. It supports the Mercedes-Benz EQA 250 (2021), Vgate iCar Pro
2S BLE adapter, generic SAE J1979 OBD-II, and a demo/simulation mode.

## Commands

```bash
swift test
xcodebuild -scheme VoltLink -destination 'platform=iOS Simulator,name=iPhone 17'
open VoltLink.xcodeproj
./scratch/repack_ipa.sh   # archive & package build/VoltLink.ipa
```

Run `swift test` after changing PID decoders, ISO-TP parsing, or SwiftData
models. `Package.swift` builds the macOS-testable `VoltLinkEngine`; the Xcode
project builds the iOS/CarPlay app. `scratch/` contains project-generation
scripts and is not part of the app build.

## Architecture

Keep the data flow one-way: BLE adapter -> parser -> vehicle profile ->
manager -> SwiftUI/CarPlay view.

- `Core/Bluetooth/BluetoothManager`: CoreBluetooth / ELM327 connection.
- `Core/OBD/ISO15765Parser`: ISO-TP frame reassembly.
- `Core/Vehicles/`: `VehicleProfile` implementations, polling commands, and
  response decoding.
- `Core/Demo/MockOBDAdapter`: simulation-backed implementation of the
  connection protocol.
- `Services/VehicleDataManager`: polling and published telemetry state.
- `Services/DTCScannerService`: DTC scanning and clearing.
- `Services/TripTrackingManager` and `Core/Location/TripLocationManager`:
  trip recording and location authorization.
- `App/AppEnvironment`: shared observable-object composition root.
- `CarPlay/`: CarPlay scene/dashboard.
- `Data/Models/`: SwiftData models; register new models in the app's model
  container.
- `UI/DesignSystem/Theme.swift`: shared colors and UI tokens.

## Implementation Rules

- Keep iOS-only APIs behind `#if canImport(CarPlay)` or `#if os(iOS)` so SPM
  tests continue to compile on macOS.
- Swift 6 concurrency is strict: protocol-conforming vehicle/connection types
  must remain `Sendable`, and published UI telemetry changes must occur on
  `@MainActor` or `DispatchQueue.main`.
- Parse multi-line ELM327 CAN responses through `ISO15765Parser`, not directly
  from raw adapter text. The EQA uses UDS Service `0x22` on CAN IDs `7E4` and
  `7E0`.
- Use `Theme.swift` tokens instead of hard-coded colors. Follow native Apple
  HIG and the existing glass/material styling.
- Background location updates require confirmed `.authorizedAlways` status;
  do not enable or request them proactively.

## Change Discipline

- Prefer the smallest change that follows existing project patterns. Avoid new
  dependencies and speculative abstractions.
- Preserve demo mode and generic OBD-II support when changing vehicle-specific
  behavior.
- Use Conventional Commits when committing:

  ```text
  type(scope): imperative summary

  Detailed explanation of the change, root cause, and affected modules.
  ```

  Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
  `chore`, `ci`. Typical scopes: `telemetry`, `obd`, `bluetooth`, `carplay`,
  `ui`, `location`, `diagnostics`, `models`, `xcodeproj`, `deps`.
