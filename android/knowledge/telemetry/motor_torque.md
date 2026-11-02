---
type: "Telemetry Metric"
title: "Motor Torque"
description: "Motor Torque telemetry metric in Nm, produced by 1 vehicle profile."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Motor Torque` (`MOTOR_TORQUE`) is a telemetry metric reported in `Nm`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `Nm` |
| Typical range | -100–400 |
| Decimal places | 0 |

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)
