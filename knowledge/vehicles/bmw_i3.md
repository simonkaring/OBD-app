---
type: "Vehicle Profile"
title: "BMW i3 (community)"
description: "BMW i3 (community) vehicle profile with 5 polling commands and 6 telemetry metrics."
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
| Registry ID | `bmw_i3` |
| Display name | BMW i3 (community) |
| Electric vehicle | Yes |
| Usable battery capacity | 37.9 kWh |
| Catalog models | 3 |
| Polling commands | 5 |

# Supported Metrics

- [HV Battery Temp](/telemetry/batteryTemp.md) — `batteryTemp` (°C)
- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [State of Charge](/telemetry/soc.md) — `soc` (%)
- [State of Health](/telemetry/soh.md) — `soh` (%)

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

- BMW i3 60Ah · 2013-2016 · Community live telemetry
- BMW i3 94Ah · 2016-2018 · Community live telemetry
- BMW i3 120Ah · 2018-2022 · Community live telemetry
