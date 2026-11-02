---
type: "Telemetry Metric"
title: "Steering Angle"
description: "Steering Angle telemetry metric in °, produced by 1 vehicle profile."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Steering Angle` (`STEERING_ANGLE`) is a telemetry metric reported in `°`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `°` |
| Typical range | -720–720 |
| Decimal places | 2 |

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEqaObdbProfile`.
