---
type: "Telemetry Metric"
title: "Motor Temp"
description: "Motor Temp telemetry metric in °C, produced by 1 vehicle profile."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Motor Temp` (`MOTOR_TEMP`) is a telemetry metric reported in `°C`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `°C` |
| Typical range | -40–150 |
| Decimal places | 0 |

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEqaObdbProfile`.
