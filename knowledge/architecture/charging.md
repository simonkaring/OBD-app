---
type: Architecture
title: "Charging and sessions"
description: "Live charging state, persisted charge sessions, power estimation, and the start-SOC indicator."
tags: [architecture, charging, telemetry]
status: stable
sources:
- id: tracker
  resource: ../Core/Telemetry/ChargingSessionTracker.swift
  title: ChargingSessionTracker
- id: sessions
  resource: ../Services/ChargingTrackingManager.swift
  title: ChargingTrackingManager
- id: model
  resource: ../Data/Models/ChargingSessionModel.swift
  title: ChargingSessionModel
---

# Two layers

1. **Live state** — `VehicleDataManager.chargingSession` is a
   `ChargingSessionState` maintained by `ChargingSessionTracker.update(...)`
   in `updateChargingSession(_:)`. It publishes `isCharging`,
   `startSOC`, `currentSOC`, `currentPowerKW`, `peakPowerKW`,
   `totalEnergyKWh`, and the recent charge curve.
2. **Persisted history** — `ChargingTrackingManager` writes
   `ChargingSessionModel` rows through SwiftData. It starts a session when
   telemetry reports charging while stationary, records snapshots, and stops
   after three consecutive non-charging snapshots (`endSessionSnapshotThreshold`)
   to avoid splitting one charge into fragments. A row stores start/end SOC,
   delivered kWh, peak/average power, and a reverse-geocoded location.

# Detection and estimation

- Charging requires the car to be stationary and energy to flow into the pack:
  pack current below `-0.5 A`, or measured/SOC-estimated charge power above
  `0.5 kW`.
- `chargePowerSource` is `.measured` when pack voltage × current or a profile
  power PID supplies the rate, and `.socEstimate` when
  `VehicleDataManager` integrates the SoC slope over at least 30 seconds
  (a 90 second history window).
- Estimated power is invalidated after 15 seconds without a fresh SOC reading,
  when the car starts moving, or when polling stops.
- Pack current sign convention: negative into the battery, positive out.

# Start SOC indicator

`ChargingLiveView` draws a tick on `BatteryLevelBar` at the level where the
current charge began:

- The level comes from `chargingSession.startSOC`, pinned when the tracker
  enters the charging state and never moved by later snapshots.
- `VehicleDataManager.displayedSOC(fromRaw:)` maps that recorded raw value onto
  the displayed scale, including the optional dashboard SOC reference offset.
- The marker and the "Started at N%" caption appear only while charging and
  only when the displayed start level is at or below the current level.

# Demo behavior

Demo telemetry bypasses the polling path, so `obdConnectionDidReceiveResponse`
also calls `updateChargingSession(_:)`; otherwise the live charging state would
stay idle in demo mode. Demo sessions are transient and cleared when demo mode
is left. `AppEnvironment.prepareDemoModeChange` saves real trip and charging
recordings before either manager switches to demo data.

Related: [Demo mode](/architecture/demo-mode.md),
[Vehicle profiles](/architecture/vehicle-profiles.md).
