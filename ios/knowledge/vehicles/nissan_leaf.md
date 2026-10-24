---
type: "Vehicle Profile"
title: "Nissan Leaf 62 kWh (OVMS)"
description: "Nissan Leaf 62 kWh (OVMS) vehicle profile with 2 polling commands and 2 telemetry metrics."
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
| Registry ID | `nissan_leaf` |
| Display name | Nissan Leaf 62 kWh (OVMS) |
| Electric vehicle | Yes |
| Usable battery capacity | 56 kWh |
| Catalog models | 2 |
| Polling commands | 2 |

# Supported Metrics

- [State of Charge](/telemetry/soc.md) — `soc` (%)
- [State of Health](/telemetry/soh.md) — `soh` (%)

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
