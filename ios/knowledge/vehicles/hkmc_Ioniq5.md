---
type: "Vehicle Profile"
title: "Hyundai/Kia E-GMP (IONIQ 5 / EV6) (hkmc_Ioniq5)"
description: "Hyundai/Kia E-GMP (IONIQ 5 / EV6) (hkmc_Ioniq5) vehicle profile with 3 polling commands and 6 telemetry metrics."
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
| Registry ID | `hkmc_Ioniq5` |
| Display name | Hyundai/Kia E-GMP (IONIQ 5 / EV6) (hkmc_Ioniq5) |
| Electric vehicle | Yes |
| Usable battery capacity | 77.4 kWh |
| Catalog models | 9 |
| Polling commands | 3 |

# Supported Metrics

- [Auxiliary 12V](/telemetry/aux12V.md) — `aux12V` (V)
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
AT Z
AT E0
AT L0
AT S1
AT H1
AT ST FF
AT SP 6
```

# Catalog Coverage

- Hyundai IONIQ 5 · 2023-2025 · Community live telemetry
- Hyundai IONIQ 5 · 2024-2025 · Community live telemetry
- Hyundai IONIQ 5 AWD · 2023-2025 · Community live telemetry
- Hyundai IONIQ 6 AWD · 2023-2025 · Community live telemetry
- Hyundai IONIQ 6 Long Range · 2023-2025 · Community live telemetry
- Hyundai IONIQ 6 Standard Range · 2023-2025 · Community live telemetry
- Hyundai IONIQ 9 Long Range AWD · 2025 · Community live telemetry
- Kia EV6 Long Range · 2022+ · Community live telemetry
- …and 1 more catalog entries
