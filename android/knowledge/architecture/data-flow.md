---
type: Architecture
title: "Data flow"
description: "How adapter bytes become a published telemetry snapshot, from BLE through ISO-TP and a vehicle profile to Compose, the companion preview and the widget."
tags: [architecture, telemetry, obd]
status: stable
sources:
- id: manager
  resource: ../app/src/main/java/com/simonkaring/voltlink/services/VehicleDataManager.kt
  title: VehicleDataManager
- id: loop
  resource: ../app/src/main/java/com/simonkaring/voltlink/services/TelemetryPollingLoop.kt
  title: Polling loop
- id: isotp
  resource: ../app/src/main/java/com/simonkaring/voltlink/core/obd/IsoTp.kt
  title: ISO-TP reassembly
---

# The chain

1. **Connection** — `services/BleObdConnection` drives the adapter: writes a command, collects
   ELM327 notifications until its terminator, and reports the raw text. Initialization commands
   (`AT Z`, `AT E0`, `AT S1`, protocol and header setup) come from the profile.
2. **Reassembly** — `core/obd/IsoTp` joins multi-frame CAN responses (flow-control / consecutive
   frames) into one payload before anything is decoded. Never parse adapter text directly in a
   screen or a view model.
3. **Decoding** — the active `VehicleProfile` turns `(command, rawResponse)` into
   `TelemetryUpdate` values. A profile may emit several updates per reply
   (`parseResponses`), e.g. pack power plus 12 V aux from one PID.
4. **Reduction** — `services/TelemetryReducer` folds updates into a `TelemetrySnapshot`,
   stamps per-field freshness and tracks which metrics are live this cycle.
5. **Publishing** — `services/VehicleDataManager` is the single façade. It exposes
   `StateFlow`s: `telemetry`, `liveMetrics`, `connectionState`, `isDemoMode`, and a
   `telemetryPublisher` for non-UI consumers.
6. **Rendering** — Compose screens collect the flows with `collectAsStateWithLifecycle()`;
   the Android Auto session, the home-screen widget and notifications read the same manager.

# Car screen

The phone app ships no car app of its own: the release manifest registers none, and the old
`car` package (templates, dials, bitmap dashboard) was removed instead of being left to
compile unused. The debug build still registers the separate IoT experiment; its shared
read-only projection, standalone preview and category-review caveats are in
[Automotive companion preview](/architecture/companion.md).

Nothing flows backwards: a screen never writes to a profile or to the adapter. User actions go
through the manager (`setDemoMode`, `selectProfile`, `selectVehicle`) or a tracker, and the new
state comes back out of the flows.

# Freshness

A metric counts as live only while it arrived in the current poll cycle; `TelemetryMetric
.isAvailable` also drops derived values (instant efficiency, regen power) when their inputs go
stale. Tiles render `--` rather than a stale number, and a value that is unknown is never
rendered as a plausible zero.

# Threading

`VehicleDataManager`, the reducer and the trackers run on the main dispatcher; BLE callbacks
are posted to it. Assets (the ABRP PID files, the DTC tables, the vehicle catalog) are parsed
off the main thread on first use.

# Demo mode

Demo mode swaps step 1–3 for `core/demo/MockDrivingSimulation`, which publishes synthetic
snapshots through the same flows. The trip and charging trackers still update their live state,
but simulated rows never reach the history database. See [Demo mode](/architecture/demo-mode.md).

# Recording and privacy

- Charging sessions report `averagePowerKW` as delivered energy over elapsed time
  (`ChargingSessionMath`), not the mean of telemetry samples, so a DC taper cannot pull
  the figure below what the charger itself displays. The helper returns `null` until
  enough time has passed, and the last stored value stands.
- `ChargingTracker` captures the session's start and end battery temperature and vehicle
  range, decides the AC/DC class at close from the session's peak power against the
  estimator's DC threshold, and records a last-known position at start when location was
  already granted. That lookup never prompts or starts location updates; without a recent
  fix the session has no coordinates and the CSV leaves them blank.
- `TripTracker` integrates distance and energy through `core/telemetry/TripMath`, which
  ignores a reading whose freshness stamp is older than 15 s. A dropped speed PID therefore
  closes the recording through the stationary countdown instead of counting kilometres while
  the car is parked.
- Trip rows are written when the recording stops; while it runs, a save every 30 s appends
  only the samples recorded since the previous one (`HistoryStore.saveTripProgress`). Past
  four hours the in-memory route is thinned by half so the export keeps the whole drive, and
  `HistoryStore` reloads only the table it just wrote instead of the whole database.
- `HistoryStore` loads each archived session's curve together with its row, so the history
  card and the detail sheet draw the same scrubbable chart the live session uses. The
  monthly summary (`ChargingHistoryInsights`) sums completed sessions in the local month
  and prices them with the settings' electricity rate.
- `HistoryStore` keeps one battery-health reading per vehicle per **local** calendar
  day. The query window and the backup `dayKey` both come from `ZoneId.systemDefault()`;
  a UTC bucket merged two local days west of UTC and split one east of it.
- `TripLocationService` records only between an explicit start and stop action. The
  intent is mapped by `TripLocationCommand`, which answers `IGNORE` for anything else —
  including the null intent a sticky restart would deliver — and the service returns
  `START_NOT_STICKY`, because the trip lives in `TripTracker` and does not survive the
  process. A phantom restart would otherwise keep the GPS and the foreground
  notification running for a trip that no longer exists.
- Recorded history stays on the device: the manifest sets
  `android:allowBackup="false"`, so Android Auto Backup cannot copy the SQLite database
  and its GPS samples off-device. The only way history leaves is the opt-in folder
  mirror, which writes a timestamped `HistoryBackup` JSON, deletes a half-written
  document before reporting the failure, restores from the newest file that parses, and
  refuses a file above 32 MB.

Related: [Vehicle profiles](/architecture/vehicle-profiles.md), [Testing](/architecture/testing.md).
