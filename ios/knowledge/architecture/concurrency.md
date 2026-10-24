---
type: Architecture
title: "Concurrency rules"
description: "Swift 6 language-mode constraints for managers, profiles, BLE callbacks, and iOS-only APIs."
tags: [architecture, concurrency, swift]
status: stable
sources:
- id: agents
  resource: ../AGENTS.md
  title: VoltLink agent guide
- id: manager
  resource: ../Services/VehicleDataManager.swift
  title: VehicleDataManager
- id: polling
  resource: ../Services/TelemetryPollingLoop.swift
  title: TelemetryPollingLoop
---

# Language mode

Both build products now compile in **Swift 6 language mode**:

- `Package.swift` declares `swiftLanguageModes: [.v6]`, so `swift test` enforces
  complete concurrency checking on macOS.
- The generated Xcode project sets `SWIFT_VERSION = 6.0` and
  `SWIFT_STRICT_CONCURRENCY = complete` for the app and UI-test targets.

`Package.swift` builds the macOS-testable `VoltLinkEngine`; the Xcode project
builds the iOS/CarPlay app. Code in `Core`, `Services`, `Data/Models`, and `UI`
must compile for both.

- `VehicleProfile` and other protocol-conforming types stay `Sendable`.
  Profiles are immutable value types over `let` data.
- `OBDConnectionProtocol` and `OBDConnectionDelegate` are `@MainActor`. Adapter
  callbacks are delivered on the main queue because `CBCentralManager` is
  created with `queue: .main`, and the demo/test adapters complete on the main
  run loop. `sendCommand` completions are `@MainActor @Sendable`.
- `AppEnvironment`, `VehicleDataManager`, `BluetoothManager`, `MockOBDAdapter`,
  `TripTrackingManager`, `ChargingTrackingManager`, and `DTCScannerService` are
  `@MainActor`.
- `BluetoothManager` conforms to the CoreBluetooth delegate protocols with
  `@preconcurrency`; its callbacks arrive on the main queue and it uses
  `MainActor.assumeIsolated` inside framework/timer closures.
- `ChargingSessionTracker` remains `@unchecked Sendable` because its
  synchronization is owned by `VehicleDataManager`, which is main-actor isolated.
- `LiveActivityCoordinator` is main-actor isolated and uses
  `@preconcurrency import ActivityKit`: `Activity` is thread-safe but not yet
  annotated `Sendable` in the SDK. Widget files (`Widgets/`) compile only into
  the extension; `Core/Sharing` compiles into both targets and must stay free of
  app-only dependencies.

# Platform boundaries

- Keep iOS-only APIs behind `#if os(iOS)` or `#if canImport(CarPlay)` so
  `swift test` keeps compiling on macOS.
- `Theme` resolves UIKit colors only under `os(iOS)`; macOS gets plain colors.
- CarPlay scene code lives in `CarPlay/` and must not become a dependency of
  `Core` or `Services`.
- Background location updates require confirmed `.authorizedAlways` status.
  Never enable or request them proactively.

# Practical rules

- Prefer main-actor APIs over manual `DispatchQueue.main` hops. Frameworks with
  nonisolated callbacks use `MainActor.assumeIsolated` only where the callback
  queue is guaranteed.
- Polling is a cancellable `Task` (`TelemetryPollingLoop`). Do not reintroduce
  completion recursion or generation-token checks for polling; `stop()` cancels
  the task and in-flight replies are discarded. `pollingGeneration` remains only
  for invalidating profile-initialization callbacks.
- Do not hold a manager reference across an `await` without checking
  `Task.isCancelled` or the relevant session flag.
- Never block the CoreBluetooth queue; adapter I/O is callback based.
- Static SDK values that are immutable but not annotated `Sendable` (for
  example `CBUUID` constants) use `nonisolated(unsafe)` with a comment
  explaining why the value cannot mutate.

Related: [One-way data flow](/architecture/data-flow.md),
[Testing](/architecture/testing.md).
