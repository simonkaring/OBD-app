---
type: "Vehicle Profile"
title: "Deepal S05 (ABRP)"
description: "Deepal S05 (ABRP) vehicle profile with 7 polling commands and 6 telemetry metrics."
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
| Registry ID | `DEEPAL_S05` |
| Display name | Deepal S05 (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 56.1 kWh |
| Catalog models | 1 |
| Polling commands | 7 |
| ABRP definition | Bundled asset |

# Supported Metrics

- [HV Battery Temp](/telemetry/battery_temp.md) — `BATTERY_TEMP` (°C)
- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)
- [State of Health](/telemetry/soh.md) — `SOH` (%)

# Polling Commands

```text
ATSH7A1
ATCRA7A9
22F22F
22F228
22F229
22F252
22F27D
```

# Initialization Commands

```text
ATZ
ATE0
ATL0
ATS1
ATH1
ATSTFF
ATSP6
```

# Catalog Coverage

- Deepal S05 · 2024+ · Community live telemetry
