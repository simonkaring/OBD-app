---
type: "Vehicle Profile"
title: "Mini Cooper SE (ABRP)"
description: "Mini Cooper SE (ABRP) vehicle profile with 5 polling commands and 6 telemetry metrics."
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
| Registry ID | `Mini_MiniCooperSE` |
| Display name | Mini Cooper SE (ABRP) |
| Electric vehicle | Yes |
| Usable battery capacity | 28.9 kWh |
| Catalog models | 2 |
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

- Mini Cooper SE · 2023 · Community live telemetry
- Mini Cooper SE · 2024-2025 · Community live telemetry
