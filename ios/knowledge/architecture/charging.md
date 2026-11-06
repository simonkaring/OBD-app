---
type: Architecture
title: "Charging and sessions"
description: "Live charging state, persisted charge sessions, power estimation, time-to-target estimates, battery health history, and the start-SOC indicator."
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
- id: estimator
  resource: ../Core/Telemetry/ChargingTimeEstimator.swift
  title: ChargingTimeEstimator
- id: health
  resource: ../Services/BatteryHealthRecorder.swift
  title: BatteryHealthRecorder
---

# Two layers

1. **Live state** — `VehicleDataManager.chargingSession` is a
   `ChargingSessionState` maintained by `ChargingSessionTracker.update(...)`
   in `updateChargingSession(_:)`. It publishes `isCharging`,
   `startSOC`, `currentSOC`, `currentPowerKW`, `peakPowerKW`,
   `totalEnergyKWh`, and the recent charge curve.
2. **Persisted history** — `ChargingTrackingManager` writes
   `ChargingSessionModel` rows through SwiftData. It starts a session only
   after charging has been observed continuously for `startConfirmationSeconds`
   (60 s), backdating the start to the first observation, so a regen pulse on
   a stale 0 km/h wheel-speed sample cannot create history. It records
   snapshots and stops after three consecutive non-charging snapshots
   (`endSessionSnapshotThreshold`) to avoid splitting one charge into
   fragments. Sessions that end within `minimumRetainedSessionDuration` (60 s)
   without delivering `minimumRetainedSessionEnergyKWh` (0.5 kWh) are deleted
   instead of persisted and never raise a notification; demo mode starts
   recording immediately. A row stores start/end SOC, delivered kWh,
   peak/average power, a reverse-geocoded location, and a timestamped power
   curve (`ChargingSampleModel`, schema V2). `liveEnergyKWh` mirrors the active
   session's total so the Charging tab's average power uses the same integration
   that the Log persists, rather than a second kWh counter.

# Curve capture

`ChargingTrackingManager.appendCurveSample` stores one point per 1% SOC change
or 60 seconds, whichever comes first, capped at 720 points per session. The
session starts with a point at its start SOC. Sessions recorded before schema V2
simply have no samples and hide the chart.

`ChargingSpeedChart` turns those readings into a charge-power-over-time curve
(elapsed minutes on the x-axis) and is the only charge graph in the app — the
session list itself stays numeric:

- `ChargingSessionDetailView` plots `ChargingSpeedCurve.session(_:)`,
  downsampled to 240 points.
- The live Charging tab plots `ChargingSessionState.history` while charging
  through `ChargingSpeedCurve.live(_:)`, downsampled to 180 of the ~2 s tracker
  points.
- Both charts are scrubbable: dragging selects the nearest reading and shows
  elapsed time, converted charge speed, and — when the source reported it — the
  battery level. Both builders return an empty curve for fewer than two
  readings and clamp regen-direction or corrupt power readings to zero.

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

# Time to target

`ChargingTimeEstimator` answers "how long until 80% / 100%?" by integrating
1% SOC bands instead of dividing the remaining energy once by the current rate.
A single division is badly wrong on DC chargers, where the pack tapers as it
fills.

- `ChargingTarget` owns the shared preference (`charging.targetSOC`, default
  80%) and the offered values 50…100%. Settings and the Charging tab both read
  it.
- AC sessions (at or below `dcPowerThresholdKW`, 22 kW) keep their current rate.
  DC sessions either continue the negative kW-per-percent slope measured from
  the session's own curve (`observedTaperSlope`), or, when the curve is too
  short, follow an exponential taper from 80% down to `taperFloorRatio` (20% of
  the current rate) near 100%.
- Targets already reached return `0`, unusable inputs return `nil`, and an
  estimate beyond `maximumEstimate` (24 h) is rejected rather than displayed.
- `ChargingLiveView` shows the estimate to the stored target and to 100%, with
  a menu to change the target in place.
  `ChargingSessionTracker.estimatedSecondsToTarget` delegates to the same
  estimator.
- `ChargingTrackingManager.checkChargeTarget` raises the opt-in
  "Charge Target Reached" notification once per session, only when the session
  started below the target and the pack crosses it while recording. The
  comparison and the announced percentage use the displayed SOC (the saved SOC
  reference applied), so the alert agrees with the dashboard; the stored session
  keeps the raw reading.

# Battery health history

State of health was previously live-only, so degradation could never be seen.
`AppEnvironment` now samples it through `BatteryHealthRecorder`:

- One `BatteryHealthSampleModel` row per vehicle per calendar day, written at
  most every ten minutes from the telemetry stream; later readings replace that
  day's row.
- Readings outside `plausibleSOH` (50…100%) are rejected so a decode glitch
  cannot plant a fake point. Demo mode is excluded.
- `recordedDistanceKm` sums completed trips at the time of the reading. It is
  VoltLink-recorded distance, not the vehicle odometer.
- `BatteryHealthTrend.summarize` returns the change since the first reading and,
  once at least 14 days are observed, a straight-line annualized change. The
  Battery Health screen charts the samples and the Charging tab links to it.

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
