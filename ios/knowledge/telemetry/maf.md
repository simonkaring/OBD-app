---
type: "Telemetry Metric"
title: "Mass Air Flow"
description: "Mass Air Flow telemetry metric in g/s, produced by 2 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Mass Air Flow` (`maf`) is a telemetry metric reported in `g/s`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `g/s` |
| Typical range | 0–200 |
| Decimal places | 0 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/genericEV.md)
- [Generic SAE J1979 OBD-II](/vehicles/genericOBD2.md)
