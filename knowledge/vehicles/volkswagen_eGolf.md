---
type: "Vehicle Profile"
title: "Volkswagen e-Golf (ABRP)"
description: "Volkswagen e-Golf (ABRP) vehicle profile with 4 polling commands and 4 telemetry metrics."
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
| Registry ID | `volkswagen_eGolf` |
| Display name | Volkswagen e-Golf (ABRP) |
| Electric vehicle | Yes |
| Usable battery capacity | 35.8 kWh |
| Catalog models | 1 |
| Polling commands | 4 |

# Supported Metrics

- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [State of Charge](/telemetry/soc.md) — `soc` (%)

# Polling Commands

```text
03221E3B55555555
03221E3D55555555
0322028C55555555
0322744855555555
```

# Initialization Commands

```text
ATZ
ATE0
ATL0
ATSP7
ATBI
ATSH FC007B
ATCP 17
ATCAF0
ATCF 17FE7
ATCRA17FE007B
```

# Catalog Coverage

- Volkswagen e-Golf · 2015-2020 · Community live telemetry
