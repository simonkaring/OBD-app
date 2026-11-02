---
type: "Telemetry Metric"
title: "Oil Temp"
description: "Oil Temp telemetry metric in °C, produced by 2 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Oil Temp` (`OIL_TEMP`) is a telemetry metric reported in `°C`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `°C` |
| Typical range | -20–150 |
| Decimal places | 0 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/generic_ev.md)
- [Generic SAE J1979 OBD-II](/vehicles/generic_obd2.md)
