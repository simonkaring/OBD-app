---
type: "Telemetry Metric"
title: "Manifold Pressure"
description: "Manifold Pressure telemetry metric in kPa, produced by 2 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Manifold Pressure` (`MANIFOLD_PRESSURE`) is a telemetry metric reported in `kPa`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `kPa` |
| Typical range | 20–120 |
| Decimal places | 0 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/generic_ev.md)
- [Generic SAE J1979 OBD-II](/vehicles/generic_obd2.md)
