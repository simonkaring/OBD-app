---
type: "Telemetry Metric"
title: "Mass Air Flow"
description: "Mass Air Flow telemetry metric in g/s, produced by 2 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Mass Air Flow` (`MAF`) is a telemetry metric reported in `g/s`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `g/s` |
| Typical range | 0–200 |
| Decimal places | 0 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/generic_ev.md)
- [Generic SAE J1979 OBD-II](/vehicles/generic_obd2.md)
