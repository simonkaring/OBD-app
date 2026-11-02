---
type: "Telemetry Metric"
title: "Engine Load"
description: "Engine Load telemetry metric in %, produced by 2 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Engine Load` (`ENGINE_LOAD`) is a telemetry metric reported in `%`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `%` |
| Typical range | 0–100 |
| Decimal places | 0 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/generic_ev.md)
- [Generic SAE J1979 OBD-II](/vehicles/generic_obd2.md)
