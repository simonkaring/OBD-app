---
type: "Telemetry Metric"
title: "Trip Average Consumption"
description: "Trip Average Consumption telemetry metric in kWh/100km, produced by 0 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Trip Average Consumption` (`TRIP_AVERAGE_CONSUMPTION`) is a telemetry metric reported in `kWh/100km`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `kWh/100km` |
| Typical range | -40–40 |
| Decimal places | 1 |

# Produced By

No profile in the Android registry currently reports this metric.

# Notes

- The default dashboard layout shows this tile, but nothing in the Android pipeline writes `TelemetrySnapshot.tripAverageConsumption` yet, so the tile reads `--`.
