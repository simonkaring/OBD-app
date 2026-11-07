---
type: "Vehicle Profile"
title: "Hyundai/Kia E-GMP (IONIQ 5 / EV6, ABRP)"
description: "Hyundai/Kia E-GMP (IONIQ 5 / EV6, ABRP) vehicle profile with 3 polling commands and 5 telemetry metrics."
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
| Registry ID | `hkmc_Ioniq5_abrp` |
| Display name | Hyundai/Kia E-GMP (IONIQ 5 / EV6, ABRP) |
| Electric vehicle | Yes |
| Usable battery capacity | 77.4 kWh |
| Catalog models | 0 |
| Polling commands | 3 |

# Supported Metrics

- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [State of Charge](/telemetry/soc.md) — `soc` (%)
- [State of Health](/telemetry/soh.md) — `soh` (%)

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
