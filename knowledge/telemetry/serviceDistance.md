---
type: "Telemetry Metric"
title: "Distance to Service"
description: "Distance to Service telemetry metric in km, produced by 1 vehicle profile."
tags: ["telemetry-metric", "experimental"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Distance to Service` (`serviceDistance`) is a telemetry metric reported in `km`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `km` |
| Typical range | 0–60000 |
| Decimal places | 0 |

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEQAOBDbProfile`.

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
