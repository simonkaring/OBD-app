---
type: "Telemetry Metric"
title: "Barometric Pressure"
description: "Barometric Pressure telemetry metric in kPa, produced by 2 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Barometric Pressure` (`barometricPressure`) is a telemetry metric reported in `kPa`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `kPa` |
| Typical range | 20–120 |
| Decimal places | 0 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/genericEV.md)
- [Generic SAE J1979 OBD-II](/vehicles/genericOBD2.md)
