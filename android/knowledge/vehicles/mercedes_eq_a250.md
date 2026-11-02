---
type: "Vehicle Profile"
title: "Mercedes-Benz EQA 250 (2021)"
description: "Mercedes-Benz EQA 250 (2021) vehicle profile with 4 polling commands and 1 telemetry metric."
tags: ["vehicle-profile", "ev"]
sources:
- id: "registry"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/vehicles/VehicleProfileRegistry.kt"
  title: "Vehicle profile registry"
- id: "catalog"
  resource: "../app/src/main/assets/vehicle_catalog.json"
  title: "Bundled vehicle catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Profile

| Attribute | Value |
| --- | --- |
| Registry ID | `MERCEDES_EQ_A250` |
| Display name | Mercedes-Benz EQA 250 (2021) |
| Profile class | `MercedesEqa250Profile` |
| Electric vehicle | Yes |
| Usable battery capacity | 66.5 kWh |
| Catalog models | 1 |
| Polling commands | 4 |
| ABRP definition | None (compiled in) |

# Supported Metrics

- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)

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
