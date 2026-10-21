---
type: "Vehicle Profile"
title: "Honda e:Ny1 (ABRP)"
description: "Honda e:Ny1 (ABRP) vehicle profile with 7 polling commands and 0 telemetry metrics."
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
| Registry ID | `honda_eny1` |
| Display name | Honda e:Ny1 (ABRP) |
| Electric vehicle | Yes |
| Usable battery capacity | 68.8 kWh |
| Catalog models | 1 |
| Polling commands | 7 |

# Polling Commands

```text
ATSH18DA01F1
ATCRA18DAF101
22202A
ATSH18DA60F1
ATCRA18DAF160
227022
227028
```

# Initialization Commands

```text
ATD
ATE0
ATH0
ATAT1
ATAL
ATS0
ATM0
ATSH18DA01F1
ATFCSH18DA01F1
ATFCSM1
```

# Catalog Coverage

- Honda e:Ny1 · 2023+ · Community live telemetry
