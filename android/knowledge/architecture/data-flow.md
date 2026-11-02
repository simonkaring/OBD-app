---
type: Architecture
title: "Data flow"
description: "How adapter bytes become a published telemetry snapshot, from BLE through ISO-TP and a vehicle profile to Compose, the car pane and the widget."
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
snapshots through the same flows. See [Demo mode](/architecture/demo-mode.md).

Related: [Vehicle profiles](/architecture/vehicle-profiles.md), [Testing](/architecture/testing.md).
