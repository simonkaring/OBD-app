---
type: "Telemetry Metric"
title: "Motor RPM"
description: "Motor RPM telemetry metric in RPM, produced by 3 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Motor RPM` (`MOTOR_RPM`) is a telemetry metric reported in `RPM`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `RPM` |
| Typical range | 0–8000 |
| Decimal places | 0 |

# Produced By

- [Generic EV (SAE J1979)](/vehicles/generic_ev.md)
- [Generic SAE J1979 OBD-II](/vehicles/generic_obd2.md)
- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedes_eq_a_obdb.md)
