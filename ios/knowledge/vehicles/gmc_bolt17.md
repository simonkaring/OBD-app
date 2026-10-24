---
type: "Vehicle Profile"
title: "Chevrolet Bolt EV 2017 (ABRP)"
description: "Chevrolet Bolt EV 2017 (ABRP) vehicle profile with 12 polling commands and 7 telemetry metrics."
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
| Registry ID | `gmc_bolt17` |
| Display name | Chevrolet Bolt EV 2017 (ABRP) |
| Electric vehicle | Yes |
| Usable battery capacity | 60 kWh |
| Catalog models | 1 |
| Polling commands | 12 |

# Supported Metrics

- [Ambient Air Temp](/telemetry/ambientAirTemp.md) — `ambientAirTemp` (°C)
- [HV Battery Temp](/telemetry/batteryTemp.md) — `batteryTemp` (°C)
- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [Speed](/telemetry/speed.md) — `speed` (km/h)
- [State of Charge](/telemetry/soc.md) — `soc` (%)

# Polling Commands

```text
ATSH7E0
22000D
ATSH7E1
222414
222885
222889
ATSH7E4
22801F
22434F
224531
2241A3
228334
```

# Initialization Commands

```text
ATZ
ATD
ATE0
ATS0
ATAL
ATSP0
```

# Catalog Coverage

- Chevrolet Bolt EV · 2017-2018 · Community live telemetry
