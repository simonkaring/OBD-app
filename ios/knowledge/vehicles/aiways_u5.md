---
type: "Vehicle Profile"
title: "Aiways U5 (ABRP)"
description: "Aiways U5 (ABRP) vehicle profile with 11 polling commands and 6 telemetry metrics."
tags: ["vehicle-profile", "ev"]
sources:
- id: "registry"
  resource: "../Core/Vehicles/VehicleProfileRegistry.swift"
  title: "Vehicle profile registry"
- id: "catalog"
  resource: "../Data/Seed/vehicle_catalog.json"
  title: "Bundled vehicle catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Profile

| Attribute | Value |
| --- | --- |
| Registry ID | `aiways_u5` |
| Display name | Aiways U5 (ABRP) |
| Electric vehicle | Yes |
| Usable battery capacity | 63 kWh |
| Catalog models | 1 |
| Polling commands | 11 |

# Supported Metrics

- [HV Battery Temp](/telemetry/batteryTemp.md) — `batteryTemp` (°C)
- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [State of Charge](/telemetry/soc.md) — `soc` (%)
- [State of Health](/telemetry/soh.md) — `soh` (%)

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
