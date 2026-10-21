---
type: Architecture
title: "Testing and verification"
description: "Which commands to run, what each suite covers, and the OKF knowledge-bundle drift test."
tags: [architecture, testing, okf]
status: stable
sources:
- id: package
  resource: ../Package.swift
  title: Swift package manifest
- id: agents
  resource: ../AGENTS.md
  title: VoltLink agent guide
---

# Commands

```bash
swift test                                                                    # engine + UI logic on macOS
xcodebuild -scheme VoltLink -destination 'platform=iOS Simulator,name=iPhone 17' build
swift run VoltLinkCLI okf export                                              # regenerate knowledge/
swift run VoltLinkCLI okf check                                               # validate knowledge/
```

Run `swift test` after changing PID decoders, ISO-TP parsing, SwiftData models,
charging/trip tracking, or the knowledge bundle. Build the Xcode scheme for
iOS-only code (`UI`, `CarPlay`, `App`).

# Suite map (Tests/)

| Suite | Covers |
| --- | --- |
| `OBDParserTests` | ISO-TP reassembly, ELM cleaning, Mode 01/22 payloads |
| `MercedesEQAOBDbProfileTests`, `VolkswagenMEBProfileTests` | Profile decoders and plausible ranges |
| `GenericOBD2ProfileTests` | SAE J1979 fallback |
| `TripAndTelemetryTests` | Snapshot state machine, charging estimates, sessions |
| `TripPersistenceTests` | SwiftData trip/charge persistence in demo mode |
| `VehicleProfileCalibrationTests` | Initialization, calibration, SOC reference |
| `ConsumptionTelemetryTests` | Efficiency and demo simulation |
| `KnowledgeBundleTests` | OKF conformance and drift against generated concepts |
| `DashboardLayoutTests`, `ABRPProfileLoaderTests`, `BluetoothManagerTests` | Layout, equation loading, connection handling |

# Conventions

- Use `XCTest`. Mark manager-touching tests `@MainActor`.
- Inject a scripted `OBDConnectionProtocol` double (`CalibrationMockAdapter`)
  instead of the real `BluetoothManager`.
- Prefer timestamped `applyUpdates(...)` calls over sleeps to make time-based
  behavior deterministic.
- Assert on absence (`hasChargePower == false`) rather than on zero-valued
  sentinels when a value is unknown.
- When a test reproduces a bug, keep it: the suite encodes behavior contracts.

# Knowledge bundle drift

`KnowledgeBundleTests` compares `knowledge/` with `KnowledgeBundle.conceptFiles()`
and `KnowledgeBundle.indexFiles(in:)`. Any change to `VehicleProfileID`,
`TelemetryMetric`, profile commands, or `Data/Seed/dtc_definitions.json` without
re-running `okf export` fails `swift test`. Hand-authored
[architecture](/architecture/data-flow.md) concepts are indexed automatically;
add or edit them directly.

Related: [One-way data flow](/architecture/data-flow.md).
