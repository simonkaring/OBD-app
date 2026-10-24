---
type: "Telemetry Metric"
title: "Regen Power"
description: "Regen Power telemetry metric in kW, produced by 3 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Regen Power` (`regenPower`) is a telemetry metric reported in `kW`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `kW` |
| Typical range | 0–100 |
| Decimal places | 1 |

# Notes

- Derived from speed and power; `VehicleDataManager` adds it to the live metric set only while both inputs are available.

# Produced By

- [Chevrolet Bolt EV 2017 (ABRP)](/vehicles/gmc_bolt17.md)
- [Chevrolet Bolt EV 2019+ (ABRP)](/vehicles/gmc_bolt19.md)
- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
