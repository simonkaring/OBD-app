---
type: "Vehicle Profile"
title: "Jaguar I-Pace 2019 (ABRP)"
description: "Jaguar I-Pace 2019 (ABRP) vehicle profile with 18 polling commands and 7 telemetry metrics."
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
| Registry ID | `jaguar_ipace2019` |
| Display name | Jaguar I-Pace 2019 (ABRP) |
| Electric vehicle | Yes |
| Usable battery capacity | 84.7 kWh |
| Catalog models | 1 |
| Polling commands | 18 |

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
ATSH7E4
ATFCSH7E4
22490C
22490F
224918
224910
224907
22DD01
22DD09
ATSH7E5
ATFCSH7E5
22FE0C
ATSH732
ATFCSH732
22D928
ATSH733
ATFCSH733
229924
```

# Initialization Commands

```text
ATZ
ATD
ATE0
ATS0
ATAL
```

# Catalog Coverage

- Jaguar I-PACE · 2023-2024 · Community live telemetry
