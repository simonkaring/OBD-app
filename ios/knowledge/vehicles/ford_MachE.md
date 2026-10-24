---
type: "Vehicle Profile"
title: "Ford Mustang Mach-E (ABRP)"
description: "Ford Mustang Mach-E (ABRP) vehicle profile with 13 polling commands and 7 telemetry metrics."
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
| Registry ID | `ford_MachE` |
| Display name | Ford Mustang Mach-E (ABRP) |
| Electric vehicle | Yes |
| Usable battery capacity | 91 kWh |
| Catalog models | 5 |
| Polling commands | 13 |

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
ATSH7E0
221505
ATSH7E2
22480D
224851
22DD05
ATSH7E4
224800
2248F9
22490C
224845
ATSH7E6
221E12
```

# Initialization Commands

```text
ATZ
ATD
ATE0
ATS0
ATAL
ATSP6
```

# Catalog Coverage

- Ford Mustang Mach-E Extended Range · 2023-2025 · Community live telemetry
- Ford Mustang Mach-E GT · 2023-2025 · Community live telemetry
- Ford Mustang Mach-E Premium · 2023-2025 · Community live telemetry
- Ford Mustang Mach-E Select · 2023-2025 · Community live telemetry
- Ford Mustang Mach-E Select · 2023-2025 · Community live telemetry
