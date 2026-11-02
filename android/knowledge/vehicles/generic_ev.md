---
type: "Vehicle Profile"
title: "Generic EV (SAE J1979)"
description: "Generic EV (SAE J1979) vehicle profile with 15 polling commands and 15 telemetry metrics."
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
| Registry ID | `GENERIC_EV` |
| Display name | Generic EV (SAE J1979) |
| Profile class | `GenericEvProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 0 kWh |
| Catalog models | 511 |
| Polling commands | 15 |
| ABRP definition | None (compiled in) |

# Supported Metrics

- [Ambient Air Temp](/telemetry/ambient_air_temp.md) — `AMBIENT_AIR_TEMP` (°C)
- [Auxiliary 12V](/telemetry/aux_12v.md) — `AUX_12V` (V)
- [Barometric Pressure](/telemetry/barometric_pressure.md) — `BAROMETRIC_PRESSURE` (kPa)
- [Coolant Temp](/telemetry/coolant_temp.md) — `COOLANT_TEMP` (°C)
- [Engine Load](/telemetry/engine_load.md) — `ENGINE_LOAD` (%)
- [Fuel Level](/telemetry/fuel_level.md) — `FUEL_LEVEL` (%)
- [Intake Air Temp](/telemetry/intake_air_temp.md) — `INTAKE_AIR_TEMP` (°C)
- [Manifold Pressure](/telemetry/manifold_pressure.md) — `MANIFOLD_PRESSURE` (kPa)
- [Mass Air Flow](/telemetry/maf.md) — `MAF` (g/s)
- [Motor RPM](/telemetry/motor_rpm.md) — `MOTOR_RPM` (RPM)
- [Oil Temp](/telemetry/oil_temp.md) — `OIL_TEMP` (°C)
- [Speed](/telemetry/speed.md) — `SPEED` (km/h)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)
- [Throttle Position](/telemetry/throttle_position.md) — `THROTTLE_POSITION` (%)
- [Timing Advance](/telemetry/timing_advance.md) — `TIMING_ADVANCE` (°)

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

- Audi A6 E Tron Base · 2025+ · Generic OBD telemetry
- Audi A6 e-tron Avant · 2024-2025 · Generic OBD telemetry
- Audi A6 e-tron Sportback · 2024-2025 · Generic OBD telemetry
- Audi e-tron GT quattro · 2023-2025 · Generic OBD telemetry
- Audi e-tron GT RS · 2023-2025 · Generic OBD telemetry
- Audi Q6 e-tron quattro · 2024-2025 · Generic OBD telemetry
- Audi Q6 e-tron quattro Sportback · 2024-2025 · Generic OBD telemetry
- Audi Q6 e-tron SQ6 · 2025 · Generic OBD telemetry
- …and 503 more catalog entries
