---
type: "Vehicle Profile"
title: "Volkswagen e-Up! (ABRP)"
description: "Volkswagen e-Up! (ABRP) vehicle profile with 4 polling commands and 4 telemetry metrics."
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
| Registry ID | `VOLKSWAGEN_E_UP` |
| Display name | Volkswagen e-Up! (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 32.3 kWh |
| Catalog models | 1 |
| Polling commands | 4 |
| ABRP definition | Bundled asset |

# Supported Metrics

- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)

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

- Volkswagen e-Up! · 2020-2023 · Community live telemetry
