---
type: "Telemetry Metric"
title: "Fuel Level"
description: "Fuel Level telemetry metric in %, produced by 2 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Fuel Level` (`fuelLevel`) is a telemetry metric reported in `%`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `%` |
| Typical range | 0–100 |
| Decimal places | 0 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/genericEV.md)
- [Generic SAE J1979 OBD-II](/vehicles/genericOBD2.md)
