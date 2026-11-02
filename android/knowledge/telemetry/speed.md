---
type: "Telemetry Metric"
title: "Speed"
description: "Speed telemetry metric in km/h, produced by 5 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Speed` (`SPEED`) is a telemetry metric reported in `km/h`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `km/h` |
| Typical range | 0–200 |
| Decimal places | 0 |

# Produced By

- [Chevrolet Bolt EV 2017 (ABRP)](/vehicles/chevrolet_bolt_2017.md)
- [Chevrolet Bolt EV 2019+ (ABRP)](/vehicles/chevrolet_bolt.md)
- [Generic EV (SAE J1979)](/vehicles/generic_ev.md)
- [Generic SAE J1979 OBD-II](/vehicles/generic_obd2.md)
- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)
