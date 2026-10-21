---
type: "Telemetry Metric"
title: "12V Voltage (High Definition)"
description: "12V Voltage (High Definition) telemetry metric in V, produced by 1 vehicle profile."
tags: ["telemetry-metric", "experimental"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`12V Voltage (High Definition)` (`aux12VHighDefinition`) is a telemetry metric reported in `V`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `V` |
| Typical range | 0–25 |
| Decimal places | 2 |

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEQAOBDbProfile`.

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
