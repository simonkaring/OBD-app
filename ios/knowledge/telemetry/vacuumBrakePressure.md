---
type: "Telemetry Metric"
title: "Vacuum Brake Pressure"
description: "Vacuum Brake Pressure telemetry metric in bar, produced by 1 vehicle profile."
tags: ["telemetry-metric", "experimental"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Vacuum Brake Pressure` (`vacuumBrakePressure`) is a telemetry metric reported in `bar`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `bar` |
| Typical range | 0–100 |
| Decimal places | 2 |

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEQAOBDbProfile`.

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
