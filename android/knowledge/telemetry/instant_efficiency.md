---
type: "Telemetry Metric"
title: "Live Consumption"
description: "Live Consumption telemetry metric in kWh/100km, produced by 3 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Live Consumption` (`INSTANT_EFFICIENCY`) is a telemetry metric reported in `kWh/100km`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `kWh/100km` |
| Typical range | -40–40 |
| Decimal places | 1 |

# Produced By

- [Chevrolet Bolt EV 2017 (ABRP)](/vehicles/chevrolet_bolt_2017.md)
- [Chevrolet Bolt EV 2019+ (ABRP)](/vehicles/chevrolet_bolt.md)
- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)

# Notes

- Derived from speed and power; `VehicleDataManager` adds it to the live metric set only while both inputs are available.
