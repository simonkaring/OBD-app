---
type: "Vehicle Profile"
title: "Mini Cooper SE (ABRP)"
description: "Mini Cooper SE (ABRP) vehicle profile with 5 polling commands and 6 telemetry metrics."
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
| Registry ID | `MINI_COOPER_SE` |
| Display name | Mini Cooper SE (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 28.9 kWh |
| Catalog models | 2 |
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

- Mini Cooper SE · 2023 · Community live telemetry
- Mini Cooper SE · 2024-2025 · Community live telemetry
