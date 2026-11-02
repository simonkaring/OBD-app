---
type: "Telemetry Metric"
title: "Distance to Service"
description: "Distance to Service telemetry metric in km, produced by 1 vehicle profile."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Distance to Service` (`SERVICE_DISTANCE`) is a telemetry metric reported in `km`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `km` |
| Typical range | 0–60000 |
| Decimal places | 0 |

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEqaObdbProfile`.
