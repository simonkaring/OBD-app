---
type: Architecture
title: "One-way data flow"
description: "How adapter bytes become published telemetry, from BLE through ISO-TP and a vehicle profile to SwiftUI and CarPlay."
tags: [architecture, data-flow, obd]
status: stable
sources:
- id: agents
  resource: ../AGENTS.md
  title: VoltLink agent guide
- id: manager
  resource: ../Services/VehicleDataManager.swift
  title: VehicleDataManager
---

# Pipeline

VoltLink keeps data moving in one direction:

```
BLE adapter -> ISO-TP parser -> vehicle profile -> VehicleDataManager -> SwiftUI / CarPlay
```

1. `Core/Bluetooth/BluetoothManager` owns the CoreBluetooth/ELM327 connection.
2. `Services/TelemetryPollingLoop` sends profile polling commands in round-robin
   order, awaiting each reply, and keeps a short settling delay. It is a
   `@MainActor` class whose work runs in a cancellable `Task`; `stopPolling()`
   cancels it rather than relying on a generation counter.
3. `Core/OBD/ISO15765Parser` reassembles multi-frame UDS/OBD responses. Never parse
   raw multi-line adapter text directly.
4. `Core/Vehicles/<Profile>` decodes a reassembled payload into `TelemetryUpdate`
   values (`soc`, `packVoltage`, `chargingStats`, `genericPid`, ...).
5. `VehicleDataManager.applyUpdates` merges updates into `TelemetrySnapshot` and
   republishes `latestTelemetry`, `liveMetrics`, and `chargingSession`. It delegates
   the stateless pieces to `TelemetryPlausibility`, `ChargingPowerEstimator`, and
   `SOCReferenceStore`.
6. Views observe the manager through iOS 17 Observation (`@Observable`), so a view
   that reads one property is not invalidated by unrelated telemetry. Side-effect
   consumers (`AppEnvironment` recorders, CarPlay) also subscribe to
   `telemetryPublisher`, a `PassthroughSubject` emitted once per published snapshot.
7. `AppEnvironment` is the composition root that wires the manager, trip tracking,
   charging tracking, and DTC scanning together.

# Freshness and availability

- `TelemetrySnapshot` carries per-value timestamps (`socUpdatedAt`,
  `powerUpdatedAt`, `speedUpdatedAt`, ...). Consumers treat readings older than
  about 15 seconds as stale instead of showing a frozen value.
- `liveMetrics` records which metrics have decoded from the connected car.
  `TelemetryMetric.isAvailable` combines that set with freshness checks.
- `TelemetryMetric.includingDerivedMetrics` adds `instantEfficiency` and
  `regenPower` only while both `speed` and `power` are available.
- `VehicleDataManager.telemetryForDisplay` applies the optional dashboard SOC
  reference offset at presentation time only. Recordings, charging estimates,
  and `displayedSOC(fromRaw:)` derive from the same raw readings.

# Extending the flow

- New decoder output: add a `TelemetryUpdate` case, decode it in the profile,
  map it in `metrics(for:)` and `TelemetryPlausibility.isPlausible(_:)`, then
  surface it through a `TelemetryMetric`.
- New UI value: read `manager.displayedTelemetry` or `manager.latestTelemetry`
  and gate on `TelemetryMetric.isAvailable`, never on a zero sentinel.
- New non-UI consumer: subscribe to `manager.telemetryPublisher` instead of
  polling `latestTelemetry`, so it runs once per applied snapshot on the main
  actor.
- Keep the graph acyclic: views read managers; managers do not import views.
  Device writes go through `BluetoothManager` / `OBDConnectionProtocol`.

Related: [Vehicle profiles](/architecture/vehicle-profiles.md),
[Concurrency rules](/architecture/concurrency.md).
