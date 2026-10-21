---
type: "Telemetry Metric"
title: "Speed"
description: "Speed telemetry metric in km/h, produced by 5 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Speed` (`speed`) is a telemetry metric reported in `km/h`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `km/h` |
| Typical range | 0–200 |
| Decimal places | 0 |

# Produced By

- [Chevrolet Bolt EV 2017 (ABRP)](/vehicles/gmc_bolt17.md)
- [Chevrolet Bolt EV 2019+ (ABRP)](/vehicles/gmc_bolt19.md)
- [Generic EV (SAE J1979)](/vehicles/genericEV.md)
- [Generic SAE J1979 OBD-II](/vehicles/genericOBD2.md)
- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
