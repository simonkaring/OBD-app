---
type: Architecture
title: "Vehicle profiles"
description: "The VehicleProfile contract, registry IDs, ABRP profiles, EQA UDS decoding, and how to add a car."
tags: [architecture, vehicles, obd, uds]
status: stable
sources:
- id: profile
  resource: ../Core/Vehicles/VehicleProfile.swift
  title: VehicleProfile protocol
- id: registry
  resource: ../Core/Vehicles/VehicleProfileRegistry.swift
  title: VehicleProfileID registry
- id: catalog
  resource: ../Data/Seed/vehicle_catalog.json
  title: Bundled vehicle catalog
---

# Contract

`Core/Vehicles/VehicleProfile.swift` defines the protocol every car implements:

- `vehicleName`, `isElectricVehicle`, `batteryUsableCapacityKWh`
- `initializationCommands` — AT/ELM setup plus any diagnostic session entry
- `pollingCommands` — commands polled round-robin while connected
- `supportedMetrics` — the `TelemetryMetric` set this profile can decode
- `parseResponse(command:rawResponse:)` / `parseResponses(...)` — return
  `TelemetryUpdate` values from a reassembled payload

`parseResponses` exists because one CAN reply can carry several values (for
example SOC, pack current, and a charging-status bit). The default
implementation wraps the single-result `parseResponse`.

# Registry and catalog

- `VehicleProfileID` (`Core/Vehicles/VehicleProfileRegistry.swift`) is the
  stable, `Codable` identity used by settings and SwiftData. `makeProfile()`
  returns the concrete profile; some IDs share one implementation or one
  ABRP JSON file.
- `Core/Vehicles/VehicleCatalog.swift` loads `Data/Seed/vehicle_catalog.json`
  and maps catalog rows to profile IDs. A row without a registered profile
  falls back to generic telemetry.
- `ABRPProfileLoader` reads `Data/Seed/abrp_pids/*.json` (iternio
  EV-OBD-PIDs) and evaluates byte equations.
- `MercedesEQA250Profile` uses UDS Service `0x22` on CAN IDs `7E4` / `7E0`.
  `MercedesEQAOBDbProfile` is the experimental 11-bit community profile.
- `DTCScannerService` and `GenericOBD2Profile` cover SAE J1979 Mode 03/04/07
  scan and clear.

# Adding or changing a car

1. Implement or extend a `VehicleProfile`; keep it `Sendable` and immutable.
2. Register the ID in `VehicleProfileID` and `makeProfile()`.
3. Add or update catalog rows in `Data/Seed/vehicle_catalog.json`, including
   usable battery capacity, model years, and telemetry support level.
4. Extend the unit tests for decoders (see [Testing](/architecture/testing.md)).
5. Regenerate this knowledge bundle:
   `swift run voltlink-cli okf export`. Profile concepts under
   `/vehicles/` are produced from the registry, so stale docs fail `swift test`.

# Ground rules

- Validate decoded values in `VehicleDataManager.isPlausible`; a wrong scaling
  factor should surface as missing data, not garbage.
- Charge power must come from pack current/power when available. SOC-slope
  estimates are a fallback and are labelled `chargePowerSource == .socEstimate`.
- Do not remove generic OBD-II or demo support when changing one vehicle.

Related: [One-way data flow](/architecture/data-flow.md),
[Charging](/architecture/charging.md).
