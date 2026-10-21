---
type: "Telemetry Metric"
title: "Lateral Acceleration"
description: "Lateral Acceleration telemetry metric in g, produced by 1 vehicle profile."
tags: ["telemetry-metric", "experimental"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Lateral Acceleration` (`lateralAcceleration`) is a telemetry metric reported in `g`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `g` |
| Typical range | -2–2 |
| Decimal places | 2 |

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEQAOBDbProfile`.

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
