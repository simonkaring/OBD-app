---
type: "Telemetry Metric"
title: "Drive Unit Temp"
description: "Drive Unit Temp telemetry metric in °C, produced by 1 vehicle profile."
tags: ["telemetry-metric", "experimental"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Drive Unit Temp` (`driveUnitTemp`) is a telemetry metric reported in `°C`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `°C` |
| Typical range | -40–150 |
| Decimal places | 0 |

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEQAOBDbProfile`.

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
