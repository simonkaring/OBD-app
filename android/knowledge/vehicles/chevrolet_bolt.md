---
type: "Vehicle Profile"
title: "Chevrolet Bolt EV 2019+ (ABRP)"
description: "Chevrolet Bolt EV 2019+ (ABRP) vehicle profile with 12 polling commands and 7 telemetry metrics."
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
| Registry ID | `CHEVROLET_BOLT` |
| Display name | Chevrolet Bolt EV 2019+ (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 66 kWh |
| Catalog models | 6 |
| Polling commands | 12 |
| ABRP definition | Bundled asset |

# Supported Metrics

- [Ambient Air Temp](/telemetry/ambient_air_temp.md) — `AMBIENT_AIR_TEMP` (°C)
- [HV Battery Temp](/telemetry/battery_temp.md) — `BATTERY_TEMP` (°C)
- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [Speed](/telemetry/speed.md) — `SPEED` (km/h)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)

# Polling Commands

```text
ATSH7E0
22000D
ATSH7E1
222414
222885
222889
ATSH7E4
22801F
22434F
224531
2245F9
228334
```

# Initialization Commands

```text
ATZ
ATD
ATE0
ATS0
ATAL
ATSP0
```

# Catalog Coverage

- Chevrolet Bolt EUV 1LT · 2023 · Community live telemetry
- Chevrolet Bolt EUV 1LT · 2023 · Community live telemetry
- Chevrolet Bolt EUV 2LT · 2023 · Community live telemetry
- Chevrolet Bolt EV 1LT · 2023 · Community live telemetry
- Chevrolet Bolt EV 1LT · 2023 · Community live telemetry
- Chevrolet Bolt EV 2LT · 2023 · Community live telemetry
