---
type: Architecture
title: "Demo mode"
description: "How the physics simulation replaces the adapter, the four scenarios, and the manual overrides."
tags: [architecture, demo, simulation]
status: stable
sources:
- id: simulation
  resource: ../app/src/main/java/com/simonkaring/voltlink/core/demo/MockDrivingSimulation.kt
  title: Mock driving simulation
- id: sheet
  resource: ../app/src/main/java/com/simonkaring/voltlink/ui/dashboard/DemoControlsSheet.kt
  title: Demo controls sheet
---

# What demo mode is

Demo mode streams simulated telemetry so the dashboard, trips, charging and diagnostics work
without an adapter. It is the first thing a new install shows, and every UI smoke test runs in
it. `VehicleDataManager.setDemoMode(true)` drops the BLE connection and drives the flows from
`MockDrivingSimulation` instead.

# Simulation

`core/demo/MockDrivingSimulation` runs a 5 Hz tick and publishes a full `TelemetrySnapshot`
through the same `StateFlow`s the real pipeline uses, so screens cannot tell the difference.
It keeps a starting snapshot (78.5 % SoC, 368 V, 26.5 °C pack) and evolves it per scenario.

# Scenarios

| Scenario | Behaviour |
| --- | --- |
| `CITY_DRIVING` | Regen and stop-and-go city cycle; honours the manual speed, throttle and regen overrides |
| `HIGHWAY_CRUISING` | Steady 120 km/h cruise with a matching power draw |
| `DC_FAST_CHARGING` | 100 kW DC charge with the taper curve, so charging sessions and time-to-target are exercised |
| `FAULT_INJECTION` | Publishes the curated `P0A80` so the diagnostics tab has a real fault to show |

# Controls

The dashboard header's **Controls** button opens the demo sheet: scenario list, manual speed /
throttle / regen sliders (each shows `Auto` until dragged), the Demo Mode / Live Adapter switch
and Reset. The sheet scrolls when the system font scale makes it taller than the window.

# Caveats

The simulation is a process-wide singleton on `VoltLinkApplication`. Changing its scenario
changes the telemetry on every tab, so UI tests that capture several screens either reset it or
leave it alone; the screenshot harness opens the sheet without picking a scenario for exactly
that reason.

Related: [Data flow](/architecture/data-flow.md), [Testing](/architecture/testing.md).
