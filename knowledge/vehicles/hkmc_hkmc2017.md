---
type: "Vehicle Profile"
title: "Hyundai / Kia (IONIQ Electric / Soul EV 2017)"
description: "Hyundai / Kia (IONIQ Electric / Soul EV 2017) vehicle profile with 5 polling commands and 7 telemetry metrics."
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
| Registry ID | `hkmc_hkmc2017` |
| Display name | Hyundai / Kia (IONIQ Electric / Soul EV 2017) |
| Electric vehicle | Yes |
| Usable battery capacity | 28 kWh |
| Catalog models | 1 |
| Polling commands | 5 |

# Supported Metrics

- [Ambient Air Temp](/telemetry/ambientAirTemp.md) — `ambientAirTemp` (°C)
- [HV Battery Temp](/telemetry/batteryTemp.md) — `batteryTemp` (°C)
- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [State of Charge](/telemetry/soc.md) — `soc` (%)
- [State of Health](/telemetry/soh.md) — `soh` (%)

# Polling Commands

```text
ATCRA7EE
2180
ATCRA7EC
2101
2105
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

# Catalog Coverage

- Hyundai Ioniq Electric · 2017-2019 · Community live telemetry
