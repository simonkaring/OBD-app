---
type: "Telemetry Metric"
title: "Timing Advance"
description: "Timing Advance telemetry metric in °, produced by 2 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Timing Advance` (`TIMING_ADVANCE`) is a telemetry metric reported in `°`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `°` |
| Typical range | -30–60 |
| Decimal places | 0 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/generic_ev.md)
- [Generic SAE J1979 OBD-II](/vehicles/generic_obd2.md)
