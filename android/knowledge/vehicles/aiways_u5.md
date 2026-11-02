---
type: "Vehicle Profile"
title: "Aiways U5 (ABRP)"
description: "Aiways U5 (ABRP) vehicle profile with 11 polling commands and 6 telemetry metrics."
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
| Registry ID | `AIWAYS_U5` |
| Display name | Aiways U5 (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 63 kWh |
| Catalog models | 1 |
| Polling commands | 11 |
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
221000
221001
221002
221004
221005
221006
221009
221010
221202
221012
22DF05
```

# Initialization Commands

```text
ATZ
ATD0
ATE0
ATSP6
ATM0
ATS0
ATAL
ATAT1
ATST64
ATSH703
```

# Catalog Coverage

- Aiways U5 · 2020+ · Community live telemetry
