---
type: "Telemetry Metric"
title: "Trip Average Consumption"
description: "Trip Average Consumption telemetry metric in kWh/100km, produced by 22 vehicle profiles."
tags: ["telemetry-metric", "core"]
sources:
- id: "metric-catalog"
  resource: "../Core/Telemetry/TelemetryMetric.swift"
  title: "Telemetry metric catalog"
generated: { by: "voltlink-okf/1.0" }
status: "stable"
---

# Definition

`Trip Average Consumption` (`tripAverageConsumption`) is a telemetry metric reported in `kWh/100km`.

# Range

| Attribute | Value |
| --- | --- |
| Unit | `kWh/100km` |
| Typical range | -40–40 |
| Decimal places | 1 |

# Notes

- Derived by `VehicleDataManager` from power when the profile supports pack power.

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
- [Hyundai/Kia E-GMP (IONIQ 5 / EV6) (hkmc_Ioniq5)](/vehicles/hkmc_Ioniq5.md)
- [Hyundai/Kia E-GMP (IONIQ 5 / EV6) (hyundaiKiaEGMP)](/vehicles/hyundaiKiaEGMP.md)
- [Jaguar I-Pace 2019 (ABRP)](/vehicles/jaguar_ipace2019.md)
- [Jaguar I-Pace 2021+ (ABRP)](/vehicles/jaguar_ipace2021.md)
- [MG ZS EV (ABRP)](/vehicles/mg_mgzsev.md)
- [Mercedes-Benz EQA 250 (OBDb community)](/vehicles/mercedesEQAOBDb.md)
- [Mini Cooper SE (ABRP)](/vehicles/Mini_MiniCooperSE.md)
- [Renault Zoe ZE40 (ABRP)](/vehicles/renault_zoe.md)
- [Renault Zoe ZE50 (ABRP)](/vehicles/renault_zoe2.md)
- [Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagenMEB)](/vehicles/volkswagenMEB.md)
- [Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagen_MEB)](/vehicles/volkswagen_MEB.md)
- [Volkswagen e-Golf (ABRP)](/vehicles/volkswagen_eGolf.md)
- [Volkswagen e-Up! (ABRP)](/vehicles/volkswagen_eUP.md)
