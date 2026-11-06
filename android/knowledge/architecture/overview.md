---
type: Architecture
title: "Android app structure"
description: "Package layout, the one-way data flow, and which module to change for a given task."
tags: [architecture, android]
status: stable
sources:
- id: readme
  resource: ../README.md
  title: Android README and parity matrix
- id: build
  resource: ../app/build.gradle.kts
  title: App module build script
---

# Repository split

VoltLink is two independent projects. `ios/` holds the SwiftUI/CarPlay app, its Swift package
and the iOS OKF bundle; `android/` holds this Kotlin/Jetpack Compose app with its own Gradle
build. The two share no source and no build tooling — only the vehicle definitions, telemetry
semantics and the OKF concept vocabulary. Do not add Android code to `ios/` or the reverse.

# Module layout

Everything is in the single `:app` module under `com.simonkaring.voltlink`:

| Package | Responsibility |
| --- | --- |
| `core/obd` | ELM327 command framing, ISO-TP reassembly (`IsoTp`), DTC models and severity |
| `core/bluetooth` | BLE scanning/connection state types |
| `core/vehicles` | `VehicleProfile` contract, `VehicleProfileId` registry, compiled-in profiles, the ABRP profile loader, the 69-brand catalog, service reminder |
| `core/telemetry` | `TelemetrySnapshot`, `TelemetryMetric`, charging time estimation and session average power |
| `core/demo` | `MockDrivingSimulation` and the demo scenarios |
| `services` | `VehicleDataManager` (main-actor facade), the polling loop, the reducer, trip/charging trackers, DTC scanner, foreground location |
| `data` | DataStore-backed settings, dashboard and car-tile layouts, history, local DTC database |
| `ui` | Compose screens (`dashboard`, `trips`, `charging`, `diagnostics`, `settings`), shared components and the design tokens in `ui/theme/Theme.kt` |
| `car` | Retained legacy experimental templates, unregistered; the debug IoT service lives in `companion` and Play approval remains unverified |
| `companion` | Read-only projection; `src/debug` contains the standalone preview and experimental native Android Auto IoT service |
| `core/widget`, `core/shortcuts`, `core/notifications`, `core/backup`, `core/export` | platform integrations |

# Where to change what

- New or corrected PID decoding: `core/vehicles` plus a test in `app/src/test/.../core/vehicles`.
- New telemetry value: `core/telemetry/TelemetryMetric.kt` and `TelemetrySnapshot`, then
  `./gradlew testDebugUnitTest --tests '*KnowledgeBundleTest' -Pokf.export=true` to refresh
  [the telemetry reference](/telemetry/speed.md).
- New screen or widget: `ui/`, with the design tokens in `ui/theme/Theme.kt` rather than
  hard-coded colors.
- Anything that changes what the app *does* with the adapter: follow
  [Data flow](/architecture/data-flow.md) down the chain instead of reading the adapter in a
  screen.

Related: [Data flow](/architecture/data-flow.md), [Vehicle profiles](/architecture/vehicle-profiles.md),
[Demo mode](/architecture/demo-mode.md), [Testing](/architecture/testing.md).
