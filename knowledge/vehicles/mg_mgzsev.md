---
type: "Vehicle Profile"
title: "MG ZS EV (ABRP)"
description: "MG ZS EV (ABRP) vehicle profile with 15 polling commands and 7 telemetry metrics."
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
| Registry ID | `mg_mgzsev` |
| Display name | MG ZS EV (ABRP) |
| Electric vehicle | Yes |
| Usable battery capacity | 68.3 kWh |
| Catalog models | 1 |
| Polling commands | 15 |

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
ATSH781
ATFCSH781
22B042
22B043
22B061
22B046
22B056
22B048
ATSH7E3
ATFCSH7E3
22BA00
22BB05
ATSH760
ATFCSH760
22B101
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

- MG ZS EV Long Range · 2021+ · Community live telemetry
