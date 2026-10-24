---
type: "Telemetry Metric"
title: "Ambient Air Temp"
description: "Ambient Air Temp telemetry metric in °C, produced by 10 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Ambient Air Temp` (`ambientAirTemp`) is a telemetry metric reported in `°C`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `°C` |
| Typical range | -20–50 |
| Decimal places | 0 |

# Produced By

- [Chevrolet Bolt EV 2017 (ABRP)](/vehicles/gmc_bolt17.md)
- [Chevrolet Bolt EV 2019+ (ABRP)](/vehicles/gmc_bolt19.md)
- [Ford Mustang Mach-E (ABRP)](/vehicles/ford_MachE.md)
- [Generic EV (SAE J1979)](/vehicles/genericEV.md)
- [Generic SAE J1979 OBD-II](/vehicles/genericOBD2.md)
- [Hyundai / Kia (IONIQ Electric / Soul EV 2017)](/vehicles/hkmc_hkmc2017.md)
- [Hyundai / Kia (Kona / Niro EV)](/vehicles/hkmc_hkmc2019.md)
- [Jaguar I-Pace 2019 (ABRP)](/vehicles/jaguar_ipace2019.md)
- [Jaguar I-Pace 2021+ (ABRP)](/vehicles/jaguar_ipace2021.md)
- [MG ZS EV (ABRP)](/vehicles/mg_mgzsev.md)
