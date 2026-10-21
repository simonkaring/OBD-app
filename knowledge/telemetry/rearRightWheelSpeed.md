---
type: "Telemetry Metric"
title: "Rear Right Wheel Speed"
description: "Rear Right Wheel Speed telemetry metric in km/h, produced by 1 vehicle profile."
tags: ["telemetry-metric", "experimental"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Rear Right Wheel Speed` (`rearRightWheelSpeed`) is a telemetry metric reported in `km/h`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `km/h` |
| Typical range | 0–200 |
| Decimal places | 0 |

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEQAOBDbProfile`.

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
