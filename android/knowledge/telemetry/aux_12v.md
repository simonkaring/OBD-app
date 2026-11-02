---
type: "Telemetry Metric"
title: "Auxiliary 12V"
description: "Auxiliary 12V telemetry metric in V, produced by 4 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Auxiliary 12V` (`AUX_12V`) is a telemetry metric reported in `V`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `V` |
| Typical range | 9–15 |
| Decimal places | 1 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/generic_ev.md)
- [Generic SAE J1979 OBD-II](/vehicles/generic_obd2.md)
- [Hyundai/Kia E-GMP (IONIQ 5 / EV6)](/vehicles/hyundai_kia_egmp.md)
- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)
