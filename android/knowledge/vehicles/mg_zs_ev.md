---
type: "Vehicle Profile"
title: "MG ZS EV (ABRP)"
description: "MG ZS EV (ABRP) vehicle profile with 15 polling commands and 7 telemetry metrics."
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
| Registry ID | `MG_ZS_EV` |
| Display name | MG ZS EV (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 68.3 kWh |
| Catalog models | 1 |
| Polling commands | 15 |
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
ATSH781
ATFCSH781
22B042
22B043
22B061
22B046
22B056
22B048
ATSH7E3
ATFCSH7E3
22BA00
22BB05
ATSH760
ATFCSH760
22B101
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

- MG ZS EV Long Range · 2021+ · Community live telemetry
