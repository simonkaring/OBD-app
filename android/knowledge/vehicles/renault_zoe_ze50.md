---
type: "Vehicle Profile"
title: "Renault Zoe ZE50 (ABRP)"
description: "Renault Zoe ZE50 (ABRP) vehicle profile with 13 polling commands and 5 telemetry metrics."
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
| Registry ID | `RENAULT_ZOE_ZE50` |
| Display name | Renault Zoe ZE50 (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 52 kWh |
| Catalog models | 1 |
| Polling commands | 13 |
| ABRP definition | Bundled asset |

# Supported Metrics

- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)
- [State of Health](/telemetry/soh.md) — `SOH` (%)

# Polling Commands

```text
ATSHDADAF1
ATCRA18DAF1DA
ATFCSH18DADAF1
222003
2220FE
2221CC
ATSHDADBF1
ATCRA18DAF1DB
ATFCSH18DADBF1
2291C8
229003
229001
229002
```

# Initialization Commands

```text
ATZ
ATE0
ATAL
ATCP18
ATFCSD300000
ATFCSM1
ATSP7
1003
```

# Catalog Coverage

- Renault Zoe ZE50 · 2019-2024 · Community live telemetry
