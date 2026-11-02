---
type: "Telemetry Metric"
title: "Front Right Wheel Speed"
description: "Front Right Wheel Speed telemetry metric in km/h, produced by 1 vehicle profile."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Front Right Wheel Speed` (`FRONT_RIGHT_WHEEL_SPEED`) is a telemetry metric reported in `km/h`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `km/h` |
| Typical range | 0–200 |
| Decimal places | 0 |

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEqaObdbProfile`.
