---
type: "Vehicle Profile"
title: "Mercedes-Benz EQA 250 (OBDb community)"
description: "Mercedes-Benz EQA 250 (OBDb community) vehicle profile with 17 polling commands and 21 telemetry metrics."
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
| Registry ID | `mercedesEQAOBDb` |
| Display name | Mercedes-Benz EQA 250 (OBDb community) |
| Electric vehicle | Yes |
| Usable battery capacity | 66.5 kWh |
| Catalog models | 1 |
| Polling commands | 17 |

# Supported Metrics

- [12V Voltage (High Definition)](/telemetry/aux12VHighDefinition.md) — `aux12VHighDefinition` (V)
- [Auxiliary 12V](/telemetry/aux12V.md) — `aux12V` (V)
- [Brake Cylinder Pressure](/telemetry/brakeCylinderPressure.md) — `brakeCylinderPressure` (bar)
- [Coolant Temp](/telemetry/coolantTemp.md) — `coolantTemp` (°C)
- [DC Converter Requested Voltage](/telemetry/converterRequestedVoltage.md) — `converterRequestedVoltage` (V)
- [Distance to Service](/telemetry/serviceDistance.md) — `serviceDistance` (km)
- [Front Left Wheel Speed](/telemetry/frontLeftWheelSpeed.md) — `frontLeftWheelSpeed` (km/h)
- [Front Right Wheel Speed](/telemetry/frontRightWheelSpeed.md) — `frontRightWheelSpeed` (km/h)
- [Lateral Acceleration](/telemetry/lateralAcceleration.md) — `lateralAcceleration` (g)
- [Longitudinal Acceleration](/telemetry/longitudinalAcceleration.md) — `longitudinalAcceleration` (g)
- [Pack Current](/telemetry/packCurrent.md) — `packCurrent` (A)
- [Pack Voltage](/telemetry/packVoltage.md) — `packVoltage` (V)
- [Power](/telemetry/power.md) — `power` (kW)
- [Rear Left Wheel Speed](/telemetry/rearLeftWheelSpeed.md) — `rearLeftWheelSpeed` (km/h)
- [Rear Right Wheel Speed](/telemetry/rearRightWheelSpeed.md) — `rearRightWheelSpeed` (km/h)
- [Speed](/telemetry/speed.md) — `speed` (km/h)
- [State of Charge](/telemetry/soc.md) — `soc` (%)
- [Steering Angle](/telemetry/steeringAngle.md) — `steeringAngle` (°)
- [Vacuum Brake Pressure](/telemetry/vacuumBrakePressure.md) — `vacuumBrakePressure` (bar)
- [Vehicle Range](/telemetry/vehicleRange.md) — `vehicleRange` (km)
- [Yaw Rate](/telemetry/yawRate.md) — `yawRate` (g)

# Polling Commands

```text
AT CRA 7EA
AT SH 7E2
222001
222002
AT CRA 7ED
AT SH 7E5
226050
226075
226053
222005
222526
226502
226071
226504
AT CRA 5A4
AT SH 624
220201
```

# Initialization Commands

```text
AT Z
AT E0
AT L0
AT S1
AT H1
AT CAF 1
AT SP 6
AT ST FF
AT CFC 1
AT FCSM 0
AT CRA 7ED
AT SH 7E5
```

# Catalog Coverage

- Mercedes-Benz EQA 250 (OBDb community) · 2021 · experimental · Community live telemetry
