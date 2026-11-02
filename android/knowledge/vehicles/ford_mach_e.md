---
type: "Vehicle Profile"
title: "Ford Mustang Mach-E (ABRP)"
description: "Ford Mustang Mach-E (ABRP) vehicle profile with 13 polling commands and 7 telemetry metrics."
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
| Registry ID | `FORD_MACH_E` |
| Display name | Ford Mustang Mach-E (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 91 kWh |
| Catalog models | 5 |
| Polling commands | 13 |
| ABRP definition | Bundled asset |

# Supported Metrics

- [Ambient Air Temp](/telemetry/ambient_air_temp.md) — `AMBIENT_AIR_TEMP` (°C)
- [HV Battery Temp](/telemetry/battery_temp.md) — `BATTERY_TEMP` (°C)
- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)
- [State of Health](/telemetry/soh.md) — `SOH` (%)

# Polling Commands

```text
ATSH7E0
221505
ATSH7E2
22480D
224851
22DD05
ATSH7E4
224800
2248F9
22490C
224845
ATSH7E6
221E12
```

# Initialization Commands

```text
ATZ
ATD
ATE0
ATS0
ATAL
ATSP6
```

# Catalog Coverage

- Ford Mustang Mach-E Extended Range · 2023-2025 · Community live telemetry
- Ford Mustang Mach-E GT · 2023-2025 · Community live telemetry
- Ford Mustang Mach-E Premium · 2023-2025 · Community live telemetry
- Ford Mustang Mach-E Select · 2023-2025 · Community live telemetry
- Ford Mustang Mach-E Select · 2023-2025 · Community live telemetry
