---
type: "Vehicle Profile"
title: "Mercedes-Benz EQA 250 (2021)"
description: "Mercedes-Benz EQA 250 (2021) vehicle profile with 4 polling commands and 1 telemetry metrics."
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
| Registry ID | `mercedesEQA250` |
| Display name | Mercedes-Benz EQA 250 (2021) |
| Electric vehicle | Yes |
| Usable battery capacity | 66.5 kWh |
| Catalog models | 1 |
| Polling commands | 4 |

# Supported Metrics

- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)

# Polling Commands

```text
ATCRA 18DAF159
AT SH 18DA59F1
22010A
220210
```

# Initialization Commands

```text
AT Z
AT E0
AT L0
AT S1
AT H1
AT CAF 1
AT SP 7
AT CP 18
AT ST FF
ATCRA 18DAF159
AT SH 18DA59F1
AT FCSH 18DA59F1
AT FCSD 300000
AT FCSM 1
```

# Catalog Coverage

- Mercedes-Benz EQA 250 · 2021 · Verified live telemetry
