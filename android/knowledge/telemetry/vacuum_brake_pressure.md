---
type: "Telemetry Metric"
title: "Vacuum Brake Pressure"
description: "Vacuum Brake Pressure telemetry metric in bar, produced by 1 vehicle profile."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Vacuum Brake Pressure` (`VACUUM_BRAKE_PRESSURE`) is a telemetry metric reported in `bar`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `bar` |
| Typical range | 0–100 |
| Decimal places | 2 |

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEqaObdbProfile`.
