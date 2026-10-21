# Architecture
* [Charging and sessions](charging.md) - Live charging state, persisted charge sessions, power estimation, and the start-SOC indicator.
* [Concurrency rules](concurrency.md) - Swift 6 strict-concurrency constraints for managers, profiles, BLE callbacks, and iOS-only APIs.
* [Demo mode](demo-mode.md) - How the mock adapter and physics simulation replace a real BLE connection, and what stays testable.
* [One-way data flow](data-flow.md) - How adapter bytes become published telemetry, from BLE through ISO-TP and a vehicle profile to SwiftUI and CarPlay.
* [Testing and verification](testing.md) - Which commands to run, what each suite covers, and the OKF knowledge-bundle drift test.
* [Vehicle profiles](vehicle-profiles.md) - The VehicleProfile contract, registry IDs, ABRP profiles, EQA UDS decoding, and how to add a car.
