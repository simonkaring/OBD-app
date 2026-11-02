---
type: "Vehicle Profile"
title: "Mercedes-Benz EQA 250 (OBDb community)"
description: "Mercedes-Benz EQA 250 (OBDb community) vehicle profile with 21 polling commands and 25 telemetry metrics."
tags: ["vehicle-profile", "ev"]
sources:
- id: "registry"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/vehicles/VehicleProfileRegistry.kt"
  title: "Vehicle profile registry"
- id: "catalog"
  resource: "../app/src/main/assets/vehicle_catalog.json"
  title: "Bundled vehicle catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Profile

| Attribute | Value |
| --- | --- |
| Registry ID | `MERCEDES_EQ_A_OBDb` |
| Display name | Mercedes-Benz EQA 250 (OBDb community) |
| Profile class | `MercedesEqaObdbProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 66.5 kWh |
| Catalog models | 1 |
| Polling commands | 21 |
| ABRP definition | None (compiled in) |

# Supported Metrics

- [12V Voltage (High Definition)](/telemetry/aux_12v_high_definition.md) — `AUX_12V_HIGH_DEFINITION` (V)
- [Auxiliary 12V](/telemetry/aux_12v.md) — `AUX_12V` (V)
- [Brake Cylinder Pressure](/telemetry/brake_cylinder_pressure.md) — `BRAKE_CYLINDER_PRESSURE` (bar)
- [Coolant Temp](/telemetry/coolant_temp.md) — `COOLANT_TEMP` (°C)
- [DC Converter Requested Voltage](/telemetry/converter_requested_voltage.md) — `CONVERTER_REQUESTED_VOLTAGE` (V)
- [Distance to Service](/telemetry/service_distance.md) — `SERVICE_DISTANCE` (km)
- [Drive Unit Temp](/telemetry/drive_unit_temp.md) — `DRIVE_UNIT_TEMP` (°C)
- [Front Left Wheel Speed](/telemetry/front_left_wheel_speed.md) — `FRONT_LEFT_WHEEL_SPEED` (km/h)
- [Front Right Wheel Speed](/telemetry/front_right_wheel_speed.md) — `FRONT_RIGHT_WHEEL_SPEED` (km/h)
- [Lateral Acceleration](/telemetry/lateral_acceleration.md) — `LATERAL_ACCELERATION` (g)
- [Longitudinal Acceleration](/telemetry/longitudinal_acceleration.md) — `LONGITUDINAL_ACCELERATION` (g)
- [Motor RPM](/telemetry/motor_rpm.md) — `MOTOR_RPM` (RPM)
- [Motor Temp](/telemetry/motor_temp.md) — `MOTOR_TEMP` (°C)
- [Motor Torque](/telemetry/motor_torque.md) — `MOTOR_TORQUE` (Nm)
- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [Rear Left Wheel Speed](/telemetry/rear_left_wheel_speed.md) — `REAR_LEFT_WHEEL_SPEED` (km/h)
- [Rear Right Wheel Speed](/telemetry/rear_right_wheel_speed.md) — `REAR_RIGHT_WHEEL_SPEED` (km/h)
- [Speed](/telemetry/speed.md) — `SPEED` (km/h)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)
- [Steering Angle](/telemetry/steering_angle.md) — `STEERING_ANGLE` (°)
- [Vacuum Brake Pressure](/telemetry/vacuum_brake_pressure.md) — `VACUUM_BRAKE_PRESSURE` (bar)
- [Vehicle Range](/telemetry/vehicle_range.md) — `VEHICLE_RANGE` (km)
- [Yaw Rate](/telemetry/yaw_rate.md) — `YAW_RATE` (g)

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
222525
AT CRA 5A4
AT SH 624
220201
220200
220205
220207
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
