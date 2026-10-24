---
type: "Telemetry Metric"
title: "Live Consumption"
description: "Live Consumption telemetry metric in kWh/100km, produced by 3 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Live Consumption` (`instantEfficiency`) is a telemetry metric reported in `kWh/100km`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `kWh/100km` |
| Typical range | -40–40 |
| Decimal places | 1 |

# Notes

- Derived from speed and power; `VehicleDataManager` adds it to the live metric set only while both inputs are available.

# Produced By

- [Chevrolet Bolt EV 2017 (ABRP)](/vehicles/gmc_bolt17.md)
- [Chevrolet Bolt EV 2019+ (ABRP)](/vehicles/gmc_bolt19.md)
- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
