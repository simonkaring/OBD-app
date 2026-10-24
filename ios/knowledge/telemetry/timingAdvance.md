---
type: "Telemetry Metric"
title: "Timing Advance"
description: "Timing Advance telemetry metric in °, produced by 2 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Timing Advance` (`timingAdvance`) is a telemetry metric reported in `°`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `°` |
| Typical range | -30–60 |
| Decimal places | 0 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/genericEV.md)
- [Generic SAE J1979 OBD-II](/vehicles/genericOBD2.md)
