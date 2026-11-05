# Architecture
* [Android app structure](overview.md) - Package layout, the one-way data flow, and which module to change for a given task.
* [Automotive companion preview](companion.md) - Read-only telemetry projection, standalone preview, and experimental debug Android Auto IoT service.
* [Data flow](data-flow.md) - How adapter bytes become a published telemetry snapshot, from BLE through ISO-TP and a vehicle profile to Compose, the companion preview and the widget.
* [Demo mode](demo-mode.md) - How the physics simulation replaces the adapter, the four scenarios, and the manual overrides.
* [Testing and verification](testing.md) - Gradle commands, phone and emulator testing, companion preview limitations, screenshots, and the OKF drift gate.
* [Vehicle profiles](vehicle-profiles.md) - The VehicleProfile contract, the registry IDs, how ABRP community definitions are loaded, and how to add a car.
