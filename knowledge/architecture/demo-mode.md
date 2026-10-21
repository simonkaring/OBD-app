---
type: Architecture
title: "Demo mode"
description: "How the mock adapter and physics simulation replace a real BLE connection, and what stays testable."
tags: [architecture, demo, simulation]
status: stable
sources:
- id: mock
  resource: ../Core/Demo/MockOBDAdapter.swift
  title: MockOBDAdapter
- id: simulation
  resource: ../Core/Demo/MockDrivingSimulation.swift
  title: MockDrivingSimulation
- id: environment
  resource: ../App/AppEnvironment.swift
  title: AppEnvironment
---

# Components

- `MockOBDAdapter` conforms to `OBDConnectionProtocol`. It does not need
  CoreBluetooth: it broadcasts simulation telemetry to the delegate and answers
  the same ELM327/UDS commands with synthesized hex responses.
- `MockDrivingSimulation` steps physics at 5 Hz and publishes a
  `TelemetrySnapshot`. Scenarios are `cityDriving`, `highwayCruising`,
  `dcFastCharging`, and `faultInjection`.
- `VehicleDataManager.toggleDemoMode(true)` swaps in a `MockOBDAdapter`, sets
  `connectionState = .demoMode`, and stops real polling.
- `AppEnvironment` subscribes to `latestTelemetry` for both real and demo
  telemetry, so trip recording and charging tracking see the simulated stream.
  `chargingTracker.isDemoMode` keeps demo sessions in memory instead of
  SwiftData.

# Scenario behavior

| Scenario | What it exercises |
| --- | --- |
| City drive | Regen power, stop-and-go speed, SoC drain |
| Highway cruise | Steady high-speed consumption |
| DC fast charging | 100 kW taper curve, 15× accelerated SOC gain, charging session |
| Fault injection | P0A80 scan/clear flow |

Demo charging is the easiest way to see charge UI: open Charge & Health and tap
**Simulate DC Fast Charging**. `MockDrivingSimulation` sets `isCharging` and a
negative pack current, so the live tracker starts a session and the start-SOC
tick appears.

# Rules

- Never require demo mode to be off for new decoding or UI logic; demo is a
  supported primary flow, not a debug flag.
- Demo state must not leak into persisted history: leaving demo mode calls
  `setDemoMode(false, endSoc:)` on both trackers after saving real recordings.
- `VehicleDataManager.clearDemoData()` resets the scenario and overrides.
- Do not rely on real BLE in tests; use `MockOBDAdapter` or a scripted
  `OBDConnectionProtocol` double.

Related: [Charging](/architecture/charging.md),
[Testing](/architecture/testing.md).
