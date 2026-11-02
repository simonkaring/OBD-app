---
type: "Vehicle Profile"
title: "BYD Atto 3 / Yuan Plus (ABRP)"
description: "BYD Atto 3 / Yuan Plus (ABRP) vehicle profile with 4 polling commands and 5 telemetry metrics."
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
| Registry ID | `BYD_ATTO3` |
| Display name | BYD Atto 3 / Yuan Plus (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 60.5 kWh |
| Catalog models | 4 |
| Polling commands | 4 |
| ABRP definition | Bundled asset |

# Supported Metrics

- [HV Battery Temp](/telemetry/battery_temp.md) — `BATTERY_TEMP` (°C)
- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)

# Polling Commands

```text
220005
220008
220009
220032
```

# Initialization Commands

```text
ATZ
ATE0
ATL0
ATS0
ATSP6
ATSH7E7
ATCRA7EF
```

# Catalog Coverage

- BYD Yuan Plus Extended Range · 2025 · Community live telemetry
- BYD Yuan Plus Standard Range · 2023-2024 · Community live telemetry
- BYD Yuan Plus Standard Range · 2025 · Community live telemetry
- BYD Yuan Plus Standard Range Extended Range · 2023-2024 · Community live telemetry
