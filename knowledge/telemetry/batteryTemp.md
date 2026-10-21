---
type: "Telemetry Metric"
title: "HV Battery Temp"
description: "HV Battery Temp telemetry metric in °C, produced by 13 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`HV Battery Temp` (`batteryTemp`) is a telemetry metric reported in `°C`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `°C` |
| Typical range | -20–60 |
| Decimal places | 0 |

# Produced By

- [Aiways U5 (ABRP)](/vehicles/aiways_u5.md)
- [BMW i3 (community)](/vehicles/bmw_i3.md)
- [BYD Atto 3 / Yuan Plus (OVMS)](/vehicles/byd_atto3.md)
- [Chevrolet Bolt EV 2017 (ABRP)](/vehicles/gmc_bolt17.md)
- [Chevrolet Bolt EV 2019+ (ABRP)](/vehicles/gmc_bolt19.md)
- [Deepal S05 (community)](/vehicles/deepal_s05.md)
- [Ford Mustang Mach-E (ABRP)](/vehicles/ford_MachE.md)
- [Hyundai / Kia (IONIQ Electric / Soul EV 2017)](/vehicles/hkmc_hkmc2017.md)
- [Hyundai / Kia (Kona / Niro EV)](/vehicles/hkmc_hkmc2019.md)
- [Jaguar I-Pace 2019 (ABRP)](/vehicles/jaguar_ipace2019.md)
- [Jaguar I-Pace 2021+ (ABRP)](/vehicles/jaguar_ipace2021.md)
- [MG ZS EV (ABRP)](/vehicles/mg_mgzsev.md)
- [Mini Cooper SE (ABRP)](/vehicles/Mini_MiniCooperSE.md)
