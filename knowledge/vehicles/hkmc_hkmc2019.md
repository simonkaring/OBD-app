---
type: "Vehicle Profile"
title: "Hyundai / Kia (Kona / Niro EV)"
description: "Hyundai / Kia (Kona / Niro EV) vehicle profile with 5 polling commands and 7 telemetry metrics."
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
| Registry ID | `hkmc_hkmc2019` |
| Display name | Hyundai / Kia (Kona / Niro EV) |
| Electric vehicle | Yes |
| Usable battery capacity | 64 kWh |
| Catalog models | 7 |
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
ATCRA7EB
220100
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

# Catalog Coverage

- Hyundai Kona Electric · 2019-2023 · Community live telemetry
- Hyundai Kona Electric Long Range · 2023-2025 · Community live telemetry
- Hyundai Kona Electric Standard Range · 2023-2025 · Community live telemetry
- Kia e-Niro / Niro EV · 2019-2022 · Community live telemetry
- Kia e-Niro / Niro EV · 2019-2022 · Community live telemetry
- Kia Soul EV · 2020-2023 · Community live telemetry
- Kia Soul EV · 2020-2023 · Community live telemetry
