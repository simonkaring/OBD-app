---
type: "Vehicle Profile"
title: "Jaguar I-Pace 2019 (ABRP)"
description: "Jaguar I-Pace 2019 (ABRP) vehicle profile with 18 polling commands and 7 telemetry metrics."
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
| Registry ID | `JAGUAR_I_PACE_2019` |
| Display name | Jaguar I-Pace 2019 (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 84.7 kWh |
| Catalog models | 1 |
| Polling commands | 18 |
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
ATSH7E4
ATFCSH7E4
22490C
22490F
224918
224910
224907
22DD01
22DD09
ATSH7E5
ATFCSH7E5
22FE0C
ATSH732
ATFCSH732
22D928
ATSH733
ATFCSH733
229924
```

# Initialization Commands

```text
ATZ
ATD
ATE0
ATS0
ATAL
```

# Catalog Coverage

- Jaguar I-PACE · 2023-2024 · Community live telemetry
