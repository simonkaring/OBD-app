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
   delivered kWh, peak/average power, a reverse-geocoded location, and a
   power-vs-SOC curve (`ChargingSampleModel`, schema V2).

# Curve capture

`ChargingTrackingManager.appendCurveSample` stores one point per 1% SOC change
or 60 seconds, whichever comes first, capped at 720 points per session. The
session starts with a point at its start SOC. `ChargingSessionDetailView` plots
the curve with SOC on the x-axis and power converted through
`UnitPreferences` on the y-axis. Sessions recorded before schema V2 simply have
no samples and hide the chart.

`ChargingSpeedChart` reuses those samples as a charge-power-over-time curve
(elapsed minutes on the x-axis):

- The Charging log draws a compact, axis-free sparkline per session row through
  `ChargingSpeedCurve.session(_:)`, downsampled to 90 points.
- The live Charging tab plots `ChargingSessionState.history` while charging
  through `ChargingSpeedCurve.live(_:)`, downsampled to 180 of the ~2 s tracker
  points. Both builders return an empty curve for fewer than two readings, and
  both clamp regen-direction or corrupt power readings to zero.

# Elapsed time and average speed

Both charging surfaces report how long the session has run and its mean charge
speed:

- `ChargingSessionSummary.duration` formats the span from `startTime` to
  `endTime` (or to now for an active session) as `"8m"` or `"1h 05m"`.
- `ChargingSessionSummary.averagePowerKW(energyKWh:over:)` divides delivered
  energy by that span — the same ratio `ChargingTrackingManager.stopSession`
  stores in `averagePowerKW`. It returns `nil` until both energy and time are
  known, so the UI shows `—` rather than a misleading 0 kW.
- `ChargingLiveView` and the active session card tick once a second through
  `TimelineView`; completed log rows use the stored end time and need no timer.

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
