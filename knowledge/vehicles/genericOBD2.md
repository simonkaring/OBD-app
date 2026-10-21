---
type: "Vehicle Profile"
title: "Generic SAE J1979 OBD-II"
description: "Generic SAE J1979 OBD-II vehicle profile with 15 polling commands and 15 telemetry metrics."
tags: ["vehicle-profile", "ice"]
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
| Registry ID | `genericOBD2` |
| Display name | Generic SAE J1979 OBD-II |
| Electric vehicle | No |
| Usable battery capacity | 0 kWh |
| Catalog models | 1 |
| Polling commands | 15 |

# Supported Metrics

- [Ambient Air Temp](/telemetry/ambientAirTemp.md) — `ambientAirTemp` (°C)
- [Auxiliary 12V](/telemetry/aux12V.md) — `aux12V` (V)
- [Barometric Pressure](/telemetry/barometricPressure.md) — `barometricPressure` (kPa)
- [Coolant Temp](/telemetry/coolantTemp.md) — `coolantTemp` (°C)
- [Engine Load](/telemetry/engineLoad.md) — `engineLoad` (%)
- [Fuel Level](/telemetry/fuelLevel.md) — `fuelLevel` (%)
- [Intake Air Temp](/telemetry/intakeAirTemp.md) — `intakeAirTemp` (°C)
- [Manifold Pressure](/telemetry/manifoldPressure.md) — `manifoldPressure` (kPa)
- [Mass Air Flow](/telemetry/maf.md) — `maf` (g/s)
- [Motor RPM](/telemetry/motorRpm.md) — `motorRpm` (RPM)
- [Oil Temp](/telemetry/oilTemp.md) — `oilTemp` (°C)
- [Speed](/telemetry/speed.md) — `speed` (km/h)
- [State of Charge](/telemetry/soc.md) — `soc` (%)
- [Throttle Position](/telemetry/throttlePosition.md) — `throttlePosition` (%)
- [Timing Advance](/telemetry/timingAdvance.md) — `timingAdvance` (°)

# Polling Commands

```text
010D
010C
0105
0142
0104
010F
0111
012F
015B
0146
0110
010B
015C
010E
0133
```

# Initialization Commands

```text
AT Z
AT E0
AT L0
AT S1
AT SP 0
```

# Catalog Coverage

- Generic Standard SAE J1979 (Gas / Hybrid) · 1996+ · Generic OBD telemetry
