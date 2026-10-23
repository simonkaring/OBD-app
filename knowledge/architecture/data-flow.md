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
   charging tracking, and DTC scanning together. It also mirrors telemetry into
   three side outputs (throttled to one write every two seconds):
   - `SharedTelemetryStore` writes a compact snapshot into the
     `group.com.simonkaring.voltlink` app group for the widget extension. The
     snapshot stays SI and carries the user's display units, because the
     extension cannot read `UnitPreferences`; it also carries `updatedAt`, and
     the widget renders its placeholder once a snapshot is older than two
     minutes instead of showing stale values as live.
   - `SharedWidgetRefresher` asks WidgetKit for a new timeline at most once a
     minute, and only when a value the widget draws (round-SoC, charge power,
     range, speed, state flags, units) actually changed.
   - `LiveActivityCoordinator` starts/updates/ends the single trip-or-charging
     Live Activity (charging wins when both are active).

   The app group carries only that compact snapshot. `AppEnvironment` pins the
   SwiftData history store to the app's own Application Support directory so
   adding (or changing) an app group cannot make SwiftData open a new, empty
   store and orphan trips recorded by an earlier version.
8. Local notifications are edge-triggered from their owners:
   `ChargingTrackingManager` (session finished), `VehicleDataManager` via
   `onUnexpectedDisconnect` (adapter lost while a trip is recording), and
   `DTCScannerService` (fault codes found). `NotificationService` gates each on
   its Settings preference.

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
  and gate on `TelemetryMetric.isAvailable`, never on a zero sentinel. Render
  through `UnitPreferences` so metric/imperial choices apply.
- New widget field: extend `SharedTelemetrySnapshot` with a defaulted or
  `decodeIfPresent` field, then fill it in `AppEnvironment.publishSharedState`.
  Never read SwiftData or CoreBluetooth from the extension.
- New non-UI consumer: subscribe to `manager.telemetryPublisher` instead of
  polling `latestTelemetry`, so it runs once per applied snapshot on the main
  actor.
- Keep the graph acyclic: views read managers; managers do not import views.
  Device writes go through `BluetoothManager` / `OBDConnectionProtocol`.

Related: [Vehicle profiles](/architecture/vehicle-profiles.md),
[Concurrency rules](/architecture/concurrency.md).
