---
type: "Telemetry Metric"
title: "Lateral Acceleration"
description: "Lateral Acceleration telemetry metric in g, produced by 1 vehicle profile."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Lateral Acceleration` (`LATERAL_ACCELERATION`) is a telemetry metric reported in `g`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `g` |
| Typical range | -2–2 |
| Decimal places | 2 |

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEqaObdbProfile`.
