---
type: "Vehicle Profile"
title: "Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagen_MEB)"
description: "Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagen_MEB) vehicle profile with 4 polling commands and 4 telemetry metrics."
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
| Registry ID | `volkswagen_MEB` |
| Display name | Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagen_MEB) |
| Electric vehicle | Yes |
| Usable battery capacity | 77 kWh |
| Catalog models | 37 |
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

# Catalog Coverage

- Audi Q4 e-tron 40 · 2023-2025 · Community live telemetry
- Audi Q4 e-tron 40 Sportback · 2023-2025 · Community live telemetry
- Audi Q4 e-tron 50 · 2023-2025 · Community live telemetry
- Audi Q4 e-tron 50 Sportback · 2023-2025 · Community live telemetry
- Audi Q4 e-tron quattro · 2023-2025 · Community live telemetry
- Audi Q4 e-tron quattro Sportback · 2023-2025 · Community live telemetry
- Cupra Born · 2023-2025 · Community live telemetry
- Cupra Born 77 kWh · 2023-2025 · Community live telemetry
- …and 29 more catalog entries
