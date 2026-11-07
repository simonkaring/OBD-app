---
type: "Vehicle Profile"
title: "Hyundai/Kia E-GMP (IONIQ 5 / EV6, ABRP)"
description: "Hyundai/Kia E-GMP (IONIQ 5 / EV6, ABRP) vehicle profile with 3 polling commands and 5 telemetry metrics."
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
| Registry ID | `HYUNDAI_KIA_EGMP_ABRP` |
| Display name | Hyundai/Kia E-GMP (IONIQ 5 / EV6, ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 77.4 kWh |
| Catalog models | 0 |
| Polling commands | 3 |
| ABRP definition | Bundled asset |

# Supported Metrics

- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)
- [State of Health](/telemetry/soh.md) — `SOH` (%)

# Polling Commands

```text
ATCRA7EC
220101
220105
```

# Initialization Commands

```text
ATZ
ATE0
ATL0
ATS0
ATH1
ATSTFF
ATFE
ATSP6
```
