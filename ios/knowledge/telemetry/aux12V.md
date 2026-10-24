---
type: "Telemetry Metric"
title: "Auxiliary 12V"
description: "Auxiliary 12V telemetry metric in V, produced by 5 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Auxiliary 12V` (`aux12V`) is a telemetry metric reported in `V`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `V` |
| Typical range | 9–15 |
| Decimal places | 1 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/genericEV.md)
- [Generic SAE J1979 OBD-II](/vehicles/genericOBD2.md)
- [Hyundai/Kia E-GMP (IONIQ 5 / EV6) (hkmc_Ioniq5)](/vehicles/hkmc_Ioniq5.md)
- [Hyundai/Kia E-GMP (IONIQ 5 / EV6) (hyundaiKiaEGMP)](/vehicles/hyundaiKiaEGMP.md)
- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
