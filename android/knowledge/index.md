---
okf_version: "0.2"
---

# Architecture
* [Android app structure](architecture/overview.md) - Package layout, the one-way data flow, and which module to change for a given task.
* [Automotive companion preview](architecture/companion.md) - Read-only telemetry projection, standalone preview, and experimental debug Android Auto IoT service.
* [Data flow](architecture/data-flow.md) - How adapter bytes become a published telemetry snapshot, from BLE through ISO-TP and a vehicle profile to Compose, the car pane and the widget.
* [Demo mode](architecture/demo-mode.md) - How the physics simulation replaces the adapter, the four scenarios, and the manual overrides.
* [Testing and verification](architecture/testing.md) - Which Gradle commands to run, how to install on a phone or emulator and open the Android Auto head unit, what each suite covers, the screenshot harness, and the OKF drift gate for the Android bundle.
* [Vehicle profiles](architecture/vehicle-profiles.md) - The VehicleProfile contract, the registry IDs, how ABRP community definitions are loaded, and how to add a car.

# Vehicle Profiles
* [Aiways U5 (ABRP)](vehicles/aiways_u5.md) - Aiways U5 (ABRP) vehicle profile with 11 polling commands and 6 telemetry metrics.
* [BMW i3 (ABRP)](vehicles/bmw_i3.md) - BMW i3 (ABRP) vehicle profile with 5 polling commands and 6 telemetry metrics.
* [BYD Atto 3 / Yuan Plus (ABRP)](vehicles/byd_atto3.md) - BYD Atto 3 / Yuan Plus (ABRP) vehicle profile with 4 polling commands and 5 telemetry metrics.
* [Chevrolet Bolt EV 2017 (ABRP)](vehicles/chevrolet_bolt_2017.md) - Chevrolet Bolt EV 2017 (ABRP) vehicle profile with 12 polling commands and 7 telemetry metrics.
* [Chevrolet Bolt EV 2019+ (ABRP)](vehicles/chevrolet_bolt.md) - Chevrolet Bolt EV 2019+ (ABRP) vehicle profile with 12 polling commands and 7 telemetry metrics.
* [Deepal S05 (ABRP)](vehicles/deepal_s05.md) - Deepal S05 (ABRP) vehicle profile with 7 polling commands and 6 telemetry metrics.
* [Ford Mustang Mach-E (ABRP)](vehicles/ford_mach_e.md) - Ford Mustang Mach-E (ABRP) vehicle profile with 13 polling commands and 7 telemetry metrics.
* [Generic EV (SAE J1979)](vehicles/generic_ev.md) - Generic EV (SAE J1979) vehicle profile with 15 polling commands and 15 telemetry metrics.
* [Generic SAE J1979 OBD-II](vehicles/generic_obd2.md) - Generic SAE J1979 OBD-II vehicle profile with 15 polling commands and 15 telemetry metrics.
* [Honda e:Ny1 (ABRP)](vehicles/honda_e_ny1.md) - Honda e:Ny1 (ABRP) vehicle profile with 7 polling commands and 6 telemetry metrics.
* [Hyundai / Kia (IONIQ Electric / Soul EV 2017)](vehicles/hyundai_kia_2017.md) - Hyundai / Kia (IONIQ Electric / Soul EV 2017) vehicle profile with 5 polling commands and 7 telemetry metrics.
* [Hyundai / Kia (Kona / Niro EV)](vehicles/hyundai_kia_2019.md) - Hyundai / Kia (Kona / Niro EV) vehicle profile with 5 polling commands and 7 telemetry metrics.
* [Hyundai/Kia E-GMP (IONIQ 5 / EV6)](vehicles/hyundai_kia_egmp.md) - Hyundai/Kia E-GMP (IONIQ 5 / EV6) vehicle profile with 3 polling commands and 6 telemetry metrics.
* [Jaguar I-Pace 2019 (ABRP)](vehicles/jaguar_i_pace_2019.md) - Jaguar I-Pace 2019 (ABRP) vehicle profile with 18 polling commands and 7 telemetry metrics.
* [Jaguar I-Pace 2021+ (ABRP)](vehicles/jaguar_i_pace.md) - Jaguar I-Pace 2021+ (ABRP) vehicle profile with 18 polling commands and 7 telemetry metrics.
* [Mercedes-Benz EQA 250 (2021)](vehicles/mercedes_eq_a250.md) - Mercedes-Benz EQA 250 (2021) vehicle profile with 4 polling commands and 1 telemetry metric.
* [Mercedes-Benz EQA 250 (OBDb community)](vehicles/mercedes_eq_a_obdb.md) - Mercedes-Benz EQA 250 (OBDb community) vehicle profile with 21 polling commands and 25 telemetry metrics.
* [MG ZS EV (ABRP)](vehicles/mg_zs_ev.md) - MG ZS EV (ABRP) vehicle profile with 15 polling commands and 7 telemetry metrics.
* [Mini Cooper SE (ABRP)](vehicles/mini_cooper_se.md) - Mini Cooper SE (ABRP) vehicle profile with 5 polling commands and 6 telemetry metrics.
* [Nissan Leaf 62 kWh (OVMS)](vehicles/nissan_leaf_ze1.md) - Nissan Leaf 62 kWh (OVMS) vehicle profile with 2 polling commands and 2 telemetry metrics.
* [Renault Zoe ZE40 (ABRP)](vehicles/renault_zoe_ze40.md) - Renault Zoe ZE40 (ABRP) vehicle profile with 4 polling commands and 5 telemetry metrics.
* [Renault Zoe ZE50 (ABRP)](vehicles/renault_zoe_ze50.md) - Renault Zoe ZE50 (ABRP) vehicle profile with 13 polling commands and 5 telemetry metrics.
* [Volkswagen e-Golf (ABRP)](vehicles/volkswagen_e_golf.md) - Volkswagen e-Golf (ABRP) vehicle profile with 4 polling commands and 4 telemetry metrics.
* [Volkswagen e-Up! (ABRP)](vehicles/volkswagen_e_up.md) - Volkswagen e-Up! (ABRP) vehicle profile with 4 polling commands and 4 telemetry metrics.
* [Volkswagen MEB (ID.3 / ID.4 / ID.Buzz)](vehicles/volkswagen_meb.md) - Volkswagen MEB (ID.3 / ID.4 / ID.Buzz) vehicle profile with 4 polling commands and 4 telemetry metrics.

# Telemetry Metrics
* [12V Voltage (High Definition)](telemetry/aux_12v_high_definition.md) - 12V Voltage (High Definition) telemetry metric in V, produced by 1 vehicle profile.
* [Ambient Air Temp](telemetry/ambient_air_temp.md) - Ambient Air Temp telemetry metric in °C, produced by 11 vehicle profiles.
* [Auxiliary 12V](telemetry/aux_12v.md) - Auxiliary 12V telemetry metric in V, produced by 4 vehicle profiles.
* [Barometric Pressure](telemetry/barometric_pressure.md) - Barometric Pressure telemetry metric in kPa, produced by 2 vehicle profiles.
* [Battery Temp Max](telemetry/battery_temp_max.md) - Battery Temp Max telemetry metric in °C, produced by 0 vehicle profiles.
* [Battery Temp Min](telemetry/battery_temp_min.md) - Battery Temp Min telemetry metric in °C, produced by 0 vehicle profiles.
* [Brake Cylinder Pressure](telemetry/brake_cylinder_pressure.md) - Brake Cylinder Pressure telemetry metric in bar, produced by 1 vehicle profile.
* [Coolant Temp](telemetry/coolant_temp.md) - Coolant Temp telemetry metric in °C, produced by 3 vehicle profiles.
* [DC Converter Requested Voltage](telemetry/converter_requested_voltage.md) - DC Converter Requested Voltage telemetry metric in V, produced by 1 vehicle profile.
* [Distance to Service](telemetry/service_distance.md) - Distance to Service telemetry metric in km, produced by 1 vehicle profile.
* [Drive Unit Temp](telemetry/drive_unit_temp.md) - Drive Unit Temp telemetry metric in °C, produced by 1 vehicle profile.
* [Engine Load](telemetry/engine_load.md) - Engine Load telemetry metric in %, produced by 2 vehicle profiles.
* [Front Left Wheel Speed](telemetry/front_left_wheel_speed.md) - Front Left Wheel Speed telemetry metric in km/h, produced by 1 vehicle profile.
* [Front Right Wheel Speed](telemetry/front_right_wheel_speed.md) - Front Right Wheel Speed telemetry metric in km/h, produced by 1 vehicle profile.
* [Fuel Level](telemetry/fuel_level.md) - Fuel Level telemetry metric in %, produced by 2 vehicle profiles.
* [HV Battery Temp](telemetry/battery_temp.md) - HV Battery Temp telemetry metric in °C, produced by 13 vehicle profiles.
* [Intake Air Temp](telemetry/intake_air_temp.md) - Intake Air Temp telemetry metric in °C, produced by 2 vehicle profiles.
* [Lateral Acceleration](telemetry/lateral_acceleration.md) - Lateral Acceleration telemetry metric in g, produced by 1 vehicle profile.
* [Live Consumption](telemetry/instant_efficiency.md) - Live Consumption telemetry metric in kWh/100km, produced by 3 vehicle profiles.
* [Longitudinal Acceleration](telemetry/longitudinal_acceleration.md) - Longitudinal Acceleration telemetry metric in g, produced by 1 vehicle profile.
* [Manifold Pressure](telemetry/manifold_pressure.md) - Manifold Pressure telemetry metric in kPa, produced by 2 vehicle profiles.
* [Mass Air Flow](telemetry/maf.md) - Mass Air Flow telemetry metric in g/s, produced by 2 vehicle profiles.
* [Motor RPM](telemetry/motor_rpm.md) - Motor RPM telemetry metric in RPM, produced by 3 vehicle profiles.
* [Motor Temp](telemetry/motor_temp.md) - Motor Temp telemetry metric in °C, produced by 1 vehicle profile.
* [Motor Torque](telemetry/motor_torque.md) - Motor Torque telemetry metric in Nm, produced by 1 vehicle profile.
* [Oil Temp](telemetry/oil_temp.md) - Oil Temp telemetry metric in °C, produced by 2 vehicle profiles.
* [Pack Current](telemetry/pack_current.md) - Pack Current telemetry metric in A, produced by 21 vehicle profiles.
* [Pack Voltage](telemetry/pack_voltage.md) - Pack Voltage telemetry metric in V, produced by 22 vehicle profiles.
* [Power](telemetry/power.md) - Power telemetry metric in kW, produced by 21 vehicle profiles.
* [Rear Left Wheel Speed](telemetry/rear_left_wheel_speed.md) - Rear Left Wheel Speed telemetry metric in km/h, produced by 1 vehicle profile.
* [Rear Right Wheel Speed](telemetry/rear_right_wheel_speed.md) - Rear Right Wheel Speed telemetry metric in km/h, produced by 1 vehicle profile.
* [Regen Power](telemetry/regen_power.md) - Regen Power telemetry metric in kW, produced by 3 vehicle profiles.
* [Speed](telemetry/speed.md) - Speed telemetry metric in km/h, produced by 5 vehicle profiles.
* [State of Charge](telemetry/soc.md) - State of Charge telemetry metric in %, produced by 24 vehicle profiles.
* [State of Health](telemetry/soh.md) - State of Health telemetry metric in %, produced by 15 vehicle profiles.
* [Steering Angle](telemetry/steering_angle.md) - Steering Angle telemetry metric in °, produced by 1 vehicle profile.
* [Throttle Position](telemetry/throttle_position.md) - Throttle Position telemetry metric in %, produced by 2 vehicle profiles.
* [Timing Advance](telemetry/timing_advance.md) - Timing Advance telemetry metric in °, produced by 2 vehicle profiles.
* [Trip Average Consumption](telemetry/trip_average_consumption.md) - Trip Average Consumption telemetry metric in kWh/100km, produced by 0 vehicle profiles.
* [Vacuum Brake Pressure](telemetry/vacuum_brake_pressure.md) - Vacuum Brake Pressure telemetry metric in bar, produced by 1 vehicle profile.
* [Vehicle Range](telemetry/vehicle_range.md) - Vehicle Range telemetry metric in km, produced by 1 vehicle profile.
* [Yaw Rate](telemetry/yaw_rate.md) - Yaw Rate telemetry metric in g, produced by 1 vehicle profile.

# Diagnostic Trouble Codes
* [P0562](diagnostics/P0562.md) - Powertrain trouble code P0562: System Voltage Low (12V Auxiliary).
* [P0A0F](diagnostics/P0A0F.md) - Powertrain trouble code P0A0F: Engine / Drive System Failed to Start.
* [P0A1F](diagnostics/P0A1F.md) - Powertrain trouble code P0A1F: Battery Energy Control Module Fault.
* [P0A78](diagnostics/P0A78.md) - Powertrain trouble code P0A78: Drive Motor Inverter Performance.
* [P0A80](diagnostics/P0A80.md) - Powertrain trouble code P0A80: Replace Hybrid/EV Battery Pack.
* [P0A93](diagnostics/P0A93.md) - Powertrain trouble code P0A93: Drive Motor Inverter Cooling Performance.
* [U0100](diagnostics/U0100.md) - Network trouble code U0100: Lost Communication with ECM/PCM.
