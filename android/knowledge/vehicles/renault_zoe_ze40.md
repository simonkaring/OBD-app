---
type: "Vehicle Profile"
title: "Renault Zoe ZE40 (ABRP)"
description: "Renault Zoe ZE40 (ABRP) vehicle profile with 4 polling commands and 5 telemetry metrics."
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
| Registry ID | `RENAULT_ZOE_ZE40` |
| Display name | Renault Zoe ZE40 (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 41 kWh |
| Catalog models | 1 |
| Polling commands | 4 |
| ABRP definition | Bundled asset |

# Supported Metrics

- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)
- [State of Health](/telemetry/soh.md) — `SOH` (%)

# Polling Commands

```text
222003
222004
223042
222002
```

# Initialization Commands

```text
ATZ
ATE0
ATAL
ATCP18
ATFCSD300000
ATFCSM1
ATSP6
ATSH7E4
ATCRA7EC
ATFCSH7E4
10C0
```

# Catalog Coverage

- Renault Zoe ZE40 · 2017-2019 · Community live telemetry
