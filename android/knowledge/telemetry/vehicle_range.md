---
type: "Telemetry Metric"
title: "Vehicle Range"
description: "Vehicle Range telemetry metric in km, produced by 1 vehicle profile."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Vehicle Range` (`VEHICLE_RANGE`) is a telemetry metric reported in `km`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `km` |
| Typical range | 0–600 |
| Decimal places | 0 |

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)
