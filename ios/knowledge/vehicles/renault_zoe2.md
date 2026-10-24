---
type: "Vehicle Profile"
title: "Renault Zoe ZE50 (ABRP)"
description: "Renault Zoe ZE50 (ABRP) vehicle profile with 13 polling commands and 5 telemetry metrics."
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
| Registry ID | `renault_zoe2` |
| Display name | Renault Zoe ZE50 (ABRP) |
| Electric vehicle | Yes |
| Usable battery capacity | 52 kWh |
| Catalog models | 1 |
| Polling commands | 13 |

# Supported Metrics

- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [State of Charge](/telemetry/soc.md) — `soc` (%)
- [State of Health](/telemetry/soh.md) — `soh` (%)

# Polling Commands

```text
ATSHDADAF1
ATCRA18DAF1DA
ATFCSH18DADAF1
222003
2220FE
2221CC
ATSHDADBF1
ATCRA18DAF1DB
ATFCSH18DADBF1
2291C8
229003
229001
229002
```

# Initialization Commands

```text
ATZ
ATE0
ATAL
ATCP18
ATFCSD300000
ATFCSM1
ATSP7
1003
```

# Catalog Coverage

- Renault Zoe ZE50 · 2019-2024 · Community live telemetry
