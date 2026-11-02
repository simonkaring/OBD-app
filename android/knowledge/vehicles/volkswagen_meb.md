---
type: "Vehicle Profile"
title: "Volkswagen MEB (ID.3 / ID.4 / ID.Buzz)"
description: "Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) vehicle profile with 4 polling commands and 4 telemetry metrics."
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
| Registry ID | `VOLKSWAGEN_MEB` |
| Display name | Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) |
| Profile class | `VolkswagenMebProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 77 kWh |
| Catalog models | 37 |
| Polling commands | 4 |
| ABRP definition | None (compiled in) |

# Supported Metrics

- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)

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
