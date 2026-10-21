---
type: "Vehicle Profile"
title: "Renault Zoe ZE40 (ABRP)"
description: "Renault Zoe ZE40 (ABRP) vehicle profile with 4 polling commands and 5 telemetry metrics."
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
| Registry ID | `renault_zoe` |
| Display name | Renault Zoe ZE40 (ABRP) |
| Electric vehicle | Yes |
| Usable battery capacity | 41 kWh |
| Catalog models | 1 |
| Polling commands | 4 |

# Supported Metrics

- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [State of Charge](/telemetry/soc.md) — `soc` (%)
- [State of Health](/telemetry/soh.md) — `soh` (%)

# Polling Commands

```text
222003
222004
223042
222002
```

# Initialization Commands

```text
ATZ
ATE0
ATAL
ATCP18
ATFCSD300000
ATFCSM1
ATSP6
ATSH7E4
ATCRA7EC
ATFCSH7E4
10C0
```

# Catalog Coverage

- Renault Zoe ZE40 · 2017-2019 · Community live telemetry
