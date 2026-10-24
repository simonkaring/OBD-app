---
type: "Vehicle Profile"
title: "BYD Atto 3 / Yuan Plus (OVMS)"
description: "BYD Atto 3 / Yuan Plus (OVMS) vehicle profile with 4 polling commands and 5 telemetry metrics."
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
| Registry ID | `byd_atto3` |
| Display name | BYD Atto 3 / Yuan Plus (OVMS) |
| Electric vehicle | Yes |
| Usable battery capacity | 60.5 kWh |
| Catalog models | 4 |
| Polling commands | 4 |

# Supported Metrics

- [HV Battery Temp](/telemetry/batteryTemp.md) — `batteryTemp` (°C)
- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [State of Charge](/telemetry/soc.md) — `soc` (%)

# Polling Commands

```text
220005
220008
220009
220032
```

# Initialization Commands

```text
ATZ
ATE0
ATL0
ATS0
ATSP6
ATSH7E7
ATCRA7EF
```

# Catalog Coverage

- BYD Yuan Plus Extended Range · 2025 · Community live telemetry
- BYD Yuan Plus Standard Range · 2023-2024 · Community live telemetry
- BYD Yuan Plus Standard Range · 2025 · Community live telemetry
- BYD Yuan Plus Standard Range Extended Range · 2023-2024 · Community live telemetry
