---
type: "Vehicle Profile"
title: "Honda e:Ny1 (ABRP)"
description: "Honda e:Ny1 (ABRP) vehicle profile with 7 polling commands and 6 telemetry metrics."
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
| Registry ID | `HONDA_E_NY1` |
| Display name | Honda e:Ny1 (ABRP) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 68.8 kWh |
| Catalog models | 1 |
| Polling commands | 7 |
| ABRP definition | Bundled asset |

# Supported Metrics

- [Ambient Air Temp](/telemetry/ambient_air_temp.md) — `AMBIENT_AIR_TEMP` (°C)
- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)
- [State of Health](/telemetry/soh.md) — `SOH` (%)

# Polling Commands

```text
ATSH18DA01F1
ATCRA18DAF101
22202A
ATSH18DA60F1
ATCRA18DAF160
227022
227028
```

# Initialization Commands

```text
ATD
ATE0
ATH0
ATAT1
ATAL
ATS0
ATM0
ATSH18DA01F1
ATFCSH18DA01F1
ATFCSM1
```

# Catalog Coverage

- Honda e:Ny1 · 2023+ · Community live telemetry
