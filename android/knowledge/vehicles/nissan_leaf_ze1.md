---
type: "Vehicle Profile"
title: "Nissan Leaf 62 kWh (OVMS)"
description: "Nissan Leaf 62 kWh (OVMS) vehicle profile with 2 polling commands and 2 telemetry metrics."
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
| Registry ID | `NISSAN_LEAF_ZE1` |
| Display name | Nissan Leaf 62 kWh (OVMS) |
| Profile class | `NissanLeafZe1Profile` |
| Electric vehicle | Yes |
| Usable battery capacity | 56 kWh |
| Catalog models | 2 |
| Polling commands | 2 |
| ABRP definition | None (compiled in) |

# Supported Metrics

- [State of Charge](/telemetry/soc.md) — `SOC` (%)
- [State of Health](/telemetry/soh.md) — `SOH` (%)

# Polling Commands

```text
2101
2161
```

# Initialization Commands

```text
AT Z
AT E0
AT L0
AT S1
AT H1
AT SP 5
AT SH 79B
AT CRA 7BB
```

# Catalog Coverage

- Nissan LEAF · 2023-2024 · Community live telemetry
- Nissan LEAF 62 kWh · 2023-2024 · Community live telemetry
