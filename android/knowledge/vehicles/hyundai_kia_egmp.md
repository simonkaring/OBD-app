---
type: "Vehicle Profile"
title: "Hyundai/Kia E-GMP (IONIQ 5 / EV6)"
description: "Hyundai/Kia E-GMP (IONIQ 5 / EV6) vehicle profile with 3 polling commands and 6 telemetry metrics."
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
| Registry ID | `HYUNDAI_KIA_EGMP` |
| Display name | Hyundai/Kia E-GMP (IONIQ 5 / EV6) |
| Profile class | `HyundaiKiaEgmpProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 77.4 kWh |
| Catalog models | 9 |
| Polling commands | 3 |
| ABRP definition | None (compiled in) |

# Supported Metrics

- [Auxiliary 12V](/telemetry/aux_12v.md) — `AUX_12V` (V)
- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)
- [State of Health](/telemetry/soh.md) — `SOH` (%)

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
