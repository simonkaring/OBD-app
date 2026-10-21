---
type: Architecture
title: "Concurrency rules"
description: "Swift 6 strict-concurrency constraints for managers, profiles, BLE callbacks, and iOS-only APIs."
tags: [architecture, concurrency, swift]
status: stable
sources:
- id: agents
  resource: ../AGENTS.md
  title: VoltLink agent guide
- id: manager
  resource: ../Services/VehicleDataManager.swift
  title: VehicleDataManager
---

# Language mode

The project builds with Swift 6 strict concurrency. `Package.swift` builds the
macOS-testable `VoltLinkEngine`; the Xcode project builds the iOS/CarPlay app.
Code in `Core`, `Services`, `Data/Models`, and `UI` must compile for both.

- `VehicleProfile` and other protocol-conforming types must stay `Sendable`.
  Profiles are immutable value types over `let` data.
- `AppEnvironment` is `@MainActor`; it owns the managers and the SwiftData
  `ModelContainer`.
- `VehicleDataManager` and other `ObservableObject`s mutate published state on
  the main queue. BLE callbacks and timer-driven freshness checks hop back to
  `DispatchQueue.main` before touching `@Published` values.
- `ChargingSessionTracker` and `TripTrackingManager` are
  `@unchecked Sendable` because their synchronization is owned by the calling
  manager, not by internal locks. Do not call them from arbitrary threads.

# Platform boundaries

- Keep iOS-only APIs behind `#if os(iOS)` or `#if canImport(CarPlay)` so
  `swift test` keeps compiling on macOS.
- `Theme` resolves UIKit colors only under `os(iOS)`; macOS gets plain colors.
- CarPlay scene code lives in `CarPlay/` and must not become a dependency of
  `Core` or `Services`.
- Background location updates require confirmed `.authorizedAlways` status.
  Never enable or request them proactively.

# Practical rules

- Prefer `Task { @MainActor in ... }` over touching UI state from a
  completion handler.
- Do not hold a manager reference across an `await` without re-checking
  generation tokens (`pollingGeneration`, `isCalibrating`) — polling can be
  stopped or restarted while a command is in flight.
- Never block the CoreBluetooth queue; adapter I/O is callback based.

Related: [One-way data flow](/architecture/data-flow.md),
[Testing](/architecture/testing.md).
