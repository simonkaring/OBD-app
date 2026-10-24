---
type: "Vehicle Profile"
title: "Deepal S05 (community)"
description: "Deepal S05 (community) vehicle profile with 7 polling commands and 6 telemetry metrics."
tags: ["vehicle-profile", "ev"]
sources:
- id: "registry"
  resource: "../Core/Vehicles/VehicleProfileRegistry.swift"
  title: "Vehicle profile registry"
- id: "catalog"
  resource: "../Data/Seed/vehicle_catalog.json"
  title: "Bundled vehicle catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Profile

| Attribute | Value |
| --- | --- |
| Registry ID | `deepal_s05` |
| Display name | Deepal S05 (community) |
| Electric vehicle | Yes |
| Usable battery capacity | 56.1 kWh |
| Catalog models | 1 |
| Polling commands | 7 |

# Supported Metrics

- [HV Battery Temp](/telemetry/batteryTemp.md) — `batteryTemp` (°C)
- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [State of Charge](/telemetry/soc.md) — `soc` (%)
- [State of Health](/telemetry/soh.md) — `soh` (%)

# Polling Commands

```text
ATSH7A1
ATCRA7A9
22F22F
22F228
22F229
22F252
22F27D
```

# Initialization Commands

```text
ATZ
ATE0
ATL0
ATS1
ATH1
ATSTFF
ATSP6
```

# Catalog Coverage

- Deepal S05 · 2024+ · Community live telemetry
