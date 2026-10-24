---
type: "Telemetry Metric"
title: "Motor RPM"
description: "Motor RPM telemetry metric in RPM, produced by 2 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Motor RPM` (`motorRpm`) is a telemetry metric reported in `RPM`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `RPM` |
| Typical range | 0–8000 |
| Decimal places | 0 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/genericEV.md)
- [Generic SAE J1979 OBD-II](/vehicles/genericOBD2.md)
