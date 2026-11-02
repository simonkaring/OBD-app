---
type: "Telemetry Metric"
title: "DC Converter Requested Voltage"
description: "DC Converter Requested Voltage telemetry metric in V, produced by 1 vehicle profile."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`DC Converter Requested Voltage` (`CONVERTER_REQUESTED_VOLTAGE`) is a telemetry metric reported in `V`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `V` |
| Typical range | 0–25 |
| Decimal places | 2 |

# Produced By

- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)

# Notes

- Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEqaObdbProfile`.
