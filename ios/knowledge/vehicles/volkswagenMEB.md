---
type: "Vehicle Profile"
title: "Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagenMEB)"
description: "Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagenMEB) vehicle profile with 4 polling commands and 4 telemetry metrics."
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
| Registry ID | `volkswagenMEB` |
| Display name | Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagenMEB) |
| Electric vehicle | Yes |
| Usable battery capacity | 77 kWh |
| Catalog models | 0 |
| Polling commands | 4 |

# Supported Metrics

- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [State of Charge](/telemetry/soc.md) — `soc` (%)

# Polling Commands

```text
03221E3D55555555
03221E3B55555555
0322028C55555555
0322744855555555
```

# Initialization Commands

```text
AT Z
AT E0
AT L0
AT S1
AT H1
AT SP 7
AT BI
AT SH FC007B
AT CP 17
AT CAF 0
AT CF 17FE7
AT CRA 17FE007B
```
