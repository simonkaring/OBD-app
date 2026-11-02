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
without an adapter. It never starts on its own: the choice is not persisted, the app opens
disconnected, and the Settings switch (or the sheet's **Demo Mode** button) starts it. Every UI
suite flips that switch before it captures a screen. `VehicleDataManager.setDemoMode(true)`
drops the BLE connection, starts `MockDrivingSimulation` and polls it; `setDemoMode(false)` stops
the simulation and returns to the disconnected BLE adapter.

# What is not recorded

Simulated driving and charging drive the live cards but are never written to the history
database: both trackers learn about the source change before they see its first snapshot.
Switching sources closes an in-flight recording under the mode it was started in, so a measured
trip or session still saves when demo mode is switched on.

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
