---
okf_version: "0.2"
---

# Architecture
* [Charging and sessions](architecture/charging.md) - Live charging state, persisted charge sessions, power estimation, and the start-SOC indicator.
* [Concurrency rules](architecture/concurrency.md) - Swift 6 language-mode constraints for managers, profiles, BLE callbacks, and iOS-only APIs.
* [Demo mode](architecture/demo-mode.md) - How the mock adapter and physics simulation replace a real BLE connection, and what stays testable.
* [One-way data flow](architecture/data-flow.md) - How adapter bytes become published telemetry, from BLE through ISO-TP and a vehicle profile to SwiftUI and CarPlay.
* [Testing and verification](architecture/testing.md) - Which commands to run, what each suite covers, and the OKF knowledge-bundle drift test.
* [Vehicle profiles](architecture/vehicle-profiles.md) - The VehicleProfile contract, registry IDs, ABRP profiles, EQA UDS decoding, and how to add a car.

# Vehicle Profiles
* [Aiways U5 (ABRP)](vehicles/aiways_u5.md) - Aiways U5 (ABRP) vehicle profile with 11 polling commands and 6 telemetry metrics.
* [BMW i3 (community)](vehicles/bmw_i3.md) - BMW i3 (community) vehicle profile with 5 polling commands and 6 telemetry metrics.
* [BYD Atto 3 / Yuan Plus (OVMS)](vehicles/byd_atto3.md) - BYD Atto 3 / Yuan Plus (OVMS) vehicle profile with 4 polling commands and 5 telemetry metrics.
* [Chevrolet Bolt EV 2017 (ABRP)](vehicles/gmc_bolt17.md) - Chevrolet Bolt EV 2017 (ABRP) vehicle profile with 12 polling commands and 7 telemetry metrics.
* [Chevrolet Bolt EV 2019+ (ABRP)](vehicles/gmc_bolt19.md) - Chevrolet Bolt EV 2019+ (ABRP) vehicle profile with 12 polling commands and 7 telemetry metrics.
* [Deepal S05 (community)](vehicles/deepal_s05.md) - Deepal S05 (community) vehicle profile with 7 polling commands and 6 telemetry metrics.
* [Ford Mustang Mach-E (ABRP)](vehicles/ford_MachE.md) - Ford Mustang Mach-E (ABRP) vehicle profile with 13 polling commands and 7 telemetry metrics.
* [Generic EV (SAE J1979)](vehicles/genericEV.md) - Generic EV (SAE J1979) vehicle profile with 15 polling commands and 15 telemetry metrics.
* [Generic SAE J1979 OBD-II](vehicles/genericOBD2.md) - Generic SAE J1979 OBD-II vehicle profile with 15 polling commands and 15 telemetry metrics.
* [Honda e:Ny1 (ABRP)](vehicles/honda_eny1.md) - Honda e:Ny1 (ABRP) vehicle profile with 7 polling commands and 0 telemetry metrics.
* [Hyundai / Kia (IONIQ Electric / Soul EV 2017)](vehicles/hkmc_hkmc2017.md) - Hyundai / Kia (IONIQ Electric / Soul EV 2017) vehicle profile with 5 polling commands and 7 telemetry metrics.
* [Hyundai / Kia (Kona / Niro EV)](vehicles/hkmc_hkmc2019.md) - Hyundai / Kia (Kona / Niro EV) vehicle profile with 5 polling commands and 7 telemetry metrics.
* [Hyundai/Kia E-GMP (IONIQ 5 / EV6) (hkmc_Ioniq5)](vehicles/hkmc_Ioniq5.md) - Hyundai/Kia E-GMP (IONIQ 5 / EV6) (hkmc_Ioniq5) vehicle profile with 3 polling commands and 6 telemetry metrics.
* [Hyundai/Kia E-GMP (IONIQ 5 / EV6) (hyundaiKiaEGMP)](vehicles/hyundaiKiaEGMP.md) - Hyundai/Kia E-GMP (IONIQ 5 / EV6) (hyundaiKiaEGMP) vehicle profile with 3 polling commands and 6 telemetry metrics.
* [Jaguar I-Pace 2019 (ABRP)](vehicles/jaguar_ipace2019.md) - Jaguar I-Pace 2019 (ABRP) vehicle profile with 18 polling commands and 7 telemetry metrics.
* [Jaguar I-Pace 2021+ (ABRP)](vehicles/jaguar_ipace2021.md) - Jaguar I-Pace 2021+ (ABRP) vehicle profile with 18 polling commands and 7 telemetry metrics.
* [Mercedes-Benz EQA 250 (2021)](vehicles/mercedesEQA250.md) - Mercedes-Benz EQA 250 (2021) vehicle profile with 4 polling commands and 1 telemetry metrics.
* [Mercedes-Benz EQA 250 (OBDb community)](vehicles/mercedesEQAOBDb.md) - Mercedes-Benz EQA 250 (OBDb community) vehicle profile with 17 polling commands and 21 telemetry metrics.
* [MG ZS EV (ABRP)](vehicles/mg_mgzsev.md) - MG ZS EV (ABRP) vehicle profile with 15 polling commands and 7 telemetry metrics.
* [Mini Cooper SE (ABRP)](vehicles/Mini_MiniCooperSE.md) - Mini Cooper SE (ABRP) vehicle profile with 5 polling commands and 6 telemetry metrics.
* [Nissan Leaf 62 kWh (OVMS)](vehicles/nissan_leaf.md) - Nissan Leaf 62 kWh (OVMS) vehicle profile with 2 polling commands and 2 telemetry metrics.
* [Renault Zoe ZE40 (ABRP)](vehicles/renault_zoe.md) - Renault Zoe ZE40 (ABRP) vehicle profile with 4 polling commands and 5 telemetry metrics.
* [Renault Zoe ZE50 (ABRP)](vehicles/renault_zoe2.md) - Renault Zoe ZE50 (ABRP) vehicle profile with 13 polling commands and 5 telemetry metrics.
* [Volkswagen e-Golf (ABRP)](vehicles/volkswagen_eGolf.md) - Volkswagen e-Golf (ABRP) vehicle profile with 4 polling commands and 4 telemetry metrics.
* [Volkswagen e-Up! (ABRP)](vehicles/volkswagen_eUP.md) - Volkswagen e-Up! (ABRP) vehicle profile with 4 polling commands and 4 telemetry metrics.
* [Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagen_MEB)](vehicles/volkswagen_MEB.md) - Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagen_MEB) vehicle profile with 4 polling commands and 4 telemetry metrics.
* [Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagenMEB)](vehicles/volkswagenMEB.md) - Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) (volkswagenMEB) vehicle profile with 4 polling commands and 4 telemetry metrics.

# Telemetry Metrics
* [12V Voltage (High Definition)](telemetry/aux12VHighDefinition.md) - 12V Voltage (High Definition) telemetry metric in V, produced by 1 vehicle profile.
* [Ambient Air Temp](telemetry/ambientAirTemp.md) - Ambient Air Temp telemetry metric in °C, produced by 10 vehicle profiles.
* [Auxiliary 12V](telemetry/aux12V.md) - Auxiliary 12V telemetry metric in V, produced by 5 vehicle profiles.
* [Barometric Pressure](telemetry/barometricPressure.md) - Barometric Pressure telemetry metric in kPa, produced by 2 vehicle profiles.
* [Battery Temp Max](telemetry/batteryTempMax.md) - Battery Temp Max telemetry metric in °C, produced by 13 vehicle profiles.
* [Battery Temp Min](telemetry/batteryTempMin.md) - Battery Temp Min telemetry metric in °C, produced by 13 vehicle profiles.
* [Brake Cylinder Pressure](telemetry/brakeCylinderPressure.md) - Brake Cylinder Pressure telemetry metric in bar, produced by 1 vehicle profile.
* [Coolant Temp](telemetry/coolantTemp.md) - Coolant Temp telemetry metric in °C, produced by 3 vehicle profiles.
* [DC Converter Requested Voltage](telemetry/converterRequestedVoltage.md) - DC Converter Requested Voltage telemetry metric in V, produced by 1 vehicle profile.
* [Distance to Service](telemetry/serviceDistance.md) - Distance to Service telemetry metric in km, produced by 1 vehicle profile.
* [Engine Load](telemetry/engineLoad.md) - Engine Load telemetry metric in %, produced by 2 vehicle profiles.
* [Front Left Wheel Speed](telemetry/frontLeftWheelSpeed.md) - Front Left Wheel Speed telemetry metric in km/h, produced by 1 vehicle profile.
* [Front Right Wheel Speed](telemetry/frontRightWheelSpeed.md) - Front Right Wheel Speed telemetry metric in km/h, produced by 1 vehicle profile.
* [Fuel Level](telemetry/fuelLevel.md) - Fuel Level telemetry metric in %, produced by 2 vehicle profiles.
* [HV Battery Temp](telemetry/batteryTemp.md) - HV Battery Temp telemetry metric in °C, produced by 13 vehicle profiles.
* [Intake Air Temp](telemetry/intakeAirTemp.md) - Intake Air Temp telemetry metric in °C, produced by 2 vehicle profiles.
* [Lateral Acceleration](telemetry/lateralAcceleration.md) - Lateral Acceleration telemetry metric in g, produced by 1 vehicle profile.
* [Live Consumption](telemetry/instantEfficiency.md) - Live Consumption telemetry metric in kWh/100km, produced by 3 vehicle profiles.
* [Longitudinal Acceleration](telemetry/longitudinalAcceleration.md) - Longitudinal Acceleration telemetry metric in g, produced by 1 vehicle profile.
* [Manifold Pressure](telemetry/manifoldPressure.md) - Manifold Pressure telemetry metric in kPa, produced by 2 vehicle profiles.
* [Mass Air Flow](telemetry/maf.md) - Mass Air Flow telemetry metric in g/s, produced by 2 vehicle profiles.
* [Motor RPM](telemetry/motorRpm.md) - Motor RPM telemetry metric in RPM, produced by 2 vehicle profiles.
* [Motor Torque](telemetry/motorTorque.md) - Motor Torque telemetry metric in Nm, not produced by any current profile.
* [Oil Temp](telemetry/oilTemp.md) - Oil Temp telemetry metric in °C, produced by 2 vehicle profiles.
* [Pack Current](telemetry/packCurrent.md) - Pack Current telemetry metric in A, produced by 22 vehicle profiles.
* [Pack Voltage](telemetry/packVoltage.md) - Pack Voltage telemetry metric in V, produced by 23 vehicle profiles.
* [Power](telemetry/power.md) - Power telemetry metric in kW, produced by 22 vehicle profiles.
* [Rear Left Wheel Speed](telemetry/rearLeftWheelSpeed.md) - Rear Left Wheel Speed telemetry metric in km/h, produced by 1 vehicle profile.
* [Rear Right Wheel Speed](telemetry/rearRightWheelSpeed.md) - Rear Right Wheel Speed telemetry metric in km/h, produced by 1 vehicle profile.
* [Regen Power](telemetry/regenPower.md) - Regen Power telemetry metric in kW, produced by 3 vehicle profiles.
* [Speed](telemetry/speed.md) - Speed telemetry metric in km/h, produced by 5 vehicle profiles.
* [State of Charge](telemetry/soc.md) - State of Charge telemetry metric in %, produced by 25 vehicle profiles.
* [State of Health](telemetry/soh.md) - State of Health telemetry metric in %, produced by 15 vehicle profiles.
* [Steering Angle](telemetry/steeringAngle.md) - Steering Angle telemetry metric in °, produced by 1 vehicle profile.
* [Throttle Position](telemetry/throttlePosition.md) - Throttle Position telemetry metric in %, produced by 2 vehicle profiles.
* [Timing Advance](telemetry/timingAdvance.md) - Timing Advance telemetry metric in °, produced by 2 vehicle profiles.
* [Trip Average Consumption](telemetry/tripAverageConsumption.md) - Trip Average Consumption telemetry metric in kWh/100km, produced by 22 vehicle profiles.
* [Vacuum Brake Pressure](telemetry/vacuumBrakePressure.md) - Vacuum Brake Pressure telemetry metric in bar, produced by 1 vehicle profile.
* [Vehicle Range](telemetry/vehicleRange.md) - Vehicle Range telemetry metric in km, produced by 1 vehicle profile.
* [Yaw Rate](telemetry/yawRate.md) - Yaw Rate telemetry metric in g, produced by 1 vehicle profile.

# Diagnostic Trouble Codes
* [P0562](diagnostics/P0562.md) - Powertrain trouble code P0562: System Voltage Low (12V Auxiliary).
* [P0A0F](diagnostics/P0A0F.md) - Powertrain trouble code P0A0F: Engine / Drive System Failed to Start.
* [P0A1F](diagnostics/P0A1F.md) - Powertrain trouble code P0A1F: Battery Energy Control Module Fault.
* [P0A78](diagnostics/P0A78.md) - Powertrain trouble code P0A78: Drive Motor Inverter Performance.
* [P0A80](diagnostics/P0A80.md) - Powertrain trouble code P0A80: Replace Hybrid/EV Battery Pack.
* [P0A93](diagnostics/P0A93.md) - Powertrain trouble code P0A93: Drive Motor Inverter Cooling Performance.
* [U0100](diagnostics/U0100.md) - Network trouble code U0100: Lost Communication with ECM/PCM.
