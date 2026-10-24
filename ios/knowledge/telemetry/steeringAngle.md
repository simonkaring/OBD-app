---
type: "Telemetry Metric"
title: "Steering Angle"
description: "Steering Angle telemetry metric in °, produced by 1 vehicle profile."
tags: ["telemetry-metric", "experimental"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Steering Angle` (`steeringAngle`) is a telemetry metric reported in `°`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `°` |
| Typical range | -720–720 |
| Decimal places | 2 |

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEQAOBDbProfile`.

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
