---
type: "Vehicle Profile"
title: "BMW i3 (ABRP)"
description: "BMW i3 (ABRP) vehicle profile with 5 polling commands and 6 telemetry metrics."
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
| Registry ID | `BMW_I3` |
| Display name | BMW i3 (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 37.9 kWh |
| Catalog models | 3 |
| Polling commands | 5 |
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
22DDBC
22DD68
22DD69
226335
22DDC0
```

# Initialization Commands

```text
ATZ
ATD
ATE0
ATS0
ATAL
ATPBE101
ATSPB
ATBI
ATSH6F1
ATAT0
ATST0F
ATCRA607
ATCEA07
ATFCSH6F1
ATFCSD07300800
ATFCSM1
```

# Catalog Coverage

- BMW i3 120Ah · 2018-2022 · Community live telemetry
- BMW i3 60Ah · 2013-2016 · Community live telemetry
- BMW i3 94Ah · 2016-2018 · Community live telemetry
