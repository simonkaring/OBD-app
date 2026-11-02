---
type: "Vehicle Profile"
title: "Hyundai / Kia (Kona / Niro EV)"
description: "Hyundai / Kia (Kona / Niro EV) vehicle profile with 5 polling commands and 7 telemetry metrics."
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
| Registry ID | `HYUNDAI_KIA_2019` |
| Display name | Hyundai / Kia (Kona / Niro EV) |
| Profile class | `AbrpGenericProfile` |
| Electric vehicle | Yes |
| Usable battery capacity | 64 kWh |
| Catalog models | 7 |
| Polling commands | 5 |
| ABRP definition | Bundled asset |

# Supported Metrics

- [Ambient Air Temp](/telemetry/ambient_air_temp.md) — `AMBIENT_AIR_TEMP` (°C)
- [HV Battery Temp](/telemetry/battery_temp.md) — `BATTERY_TEMP` (°C)
- [Pack Current](/telemetry/pack_current.md) — `PACK_CURRENT` (A)
- [Pack Voltage](/telemetry/pack_voltage.md) — `PACK_VOLTAGE` (V)
- [Power](/telemetry/power.md) — `POWER` (kW)
- [State of Charge](/telemetry/soc.md) — `SOC` (%)
- [State of Health](/telemetry/soh.md) — `SOH` (%)

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
