---
type: "Telemetry Metric"
title: "HV Battery Temp"
description: "HV Battery Temp telemetry metric in °C, produced by 13 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../app/src/main/java/com/simonkaring/voltlink/core/telemetry/TelemetryMetric.kt"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`HV Battery Temp` (`BATTERY_TEMP`) is a telemetry metric reported in `°C`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `°C` |
| Typical range | -20–60 |
| Decimal places | 0 |

# Produced By

- [Aiways U5 (ABRP)](/vehicles/aiways_u5.md)
- [BMW i3 (ABRP)](/vehicles/bmw_i3.md)
- [BYD Atto 3 / Yuan Plus (ABRP)](/vehicles/byd_atto3.md)
- [Chevrolet Bolt EV 2017 (ABRP)](/vehicles/chevrolet_bolt_2017.md)
- [Chevrolet Bolt EV 2019+ (ABRP)](/vehicles/chevrolet_bolt.md)
- [Deepal S05 (ABRP)](/vehicles/deepal_s05.md)
- [Ford Mustang Mach-E (ABRP)](/vehicles/ford_mach_e.md)
- [Hyundai / Kia (IONIQ Electric / Soul EV 2017)](/vehicles/hyundai_kia_2017.md)
- [Hyundai / Kia (Kona / Niro EV)](/vehicles/hyundai_kia_2019.md)
- [Jaguar I-Pace 2019 (ABRP)](/vehicles/jaguar_i_pace_2019.md)
- [Jaguar I-Pace 2021+ (ABRP)](/vehicles/jaguar_i_pace.md)
- [MG ZS EV (ABRP)](/vehicles/mg_zs_ev.md)
- [Mini Cooper SE (ABRP)](/vehicles/mini_cooper_se.md)
