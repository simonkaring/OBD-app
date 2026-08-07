# VoltLink — Repository Instructions & Coding Rules

This repository contains **VoltLink**, a native Swift iOS & Apple CarPlay application for OBD-II vehicle diagnostics and live EV telemetry, optimized for the **Mercedes-Benz EQA 250 (2021)** and **Vgate iCar Pro 2S** BLE adapter.

---

## 🛠️ Technology Stack & Requirements

- **Language**: Swift 5.10 / Swift 6 (Strict Concurrency Checking Enabled)
- **UI Framework**: SwiftUI + Swift Charts + SF Symbols
- **Bluetooth**: CoreBluetooth (`CBCentralManager`, `CBPeripheral`)
- **CarPlay**: `CPTemplateApplicationSceneDelegate` + `CPGridTemplate`
- **Persistence**: SwiftData (`ModelContainer`, `@Model`, `@Relationship`)
- **Live Activities**: ActivityKit (`VoltLinkActivityAttributes`)
- **Build System**: Swift Package Manager (`Package.swift`) & Xcode 15/16+

---

## 🏗️ Architecture & Directory Structure

```
OBD-app/
├── App/                # Main SwiftUI app entry point, AppEnvironment, Info.plist
├── CarPlay/            # CarPlaySceneDelegate in-car dashboard templates
├── Core/
│   ├── Bluetooth/      # BLE GATT UUIDs & CBCentralManager connection manager
│   ├── OBD/            # Command queues, ISO-TP CAN frame parser, DTC data models
│   ├── Vehicles/       # VehicleProfile protocol & Mercedes EQA 250 UDS PID decoders
│   ├── Demo/           # Physics-based driving & 100 kW DC charging simulator
│   └── Location/       # CoreLocation route tracking
├── Data/
│   ├── Models/         # SwiftData persistence models (TripModel, SavedDTCModel)
│   ├── Repositories/   # Offline DTC JSON database loader
│   └── Seed/           # Bundled dtc_definitions.json database
├── Services/           # Telemetry publishers, trip recorders, DTC scanners
├── UI/
│   ├── DesignSystem/   # Theme tokens, Glassmorphism card modifiers, Animated Gauges
│   ├── Dashboard/      # Live gauges, Swift Charts line graph, HUD mode
│   ├── Diagnostics/    # DTC trouble code scanner & detail sheets
│   ├── Trips/          # Recorded trip log history
│   ├── Charging/       # Fast-charging monitor & battery health report
│   ├── DemoHUD/        # Interactive simulation controls sheet
│   └── Settings/       # App settings & BLE device scanner
└── Tests/              # XCTest suite (OBDParserTests.swift)
```

---

## 🎨 Design & Aesthetic Guidelines

1. **Native Apple Aesthetics**: Follow Apple Human Interface Guidelines (HIG). Use SF Pro Rounded typography, variable SF Symbols, and frosted glassmorphism (`.ultraThinMaterial`).
2. **Automotive Color Tokens**:
   - Primary Background: Dark Slate (`#0D121A`)
   - Electric Telemetry Accent: Electric Cyan (`#00F0FF`)
   - Regenerative Braking Accent: Emerald Green (`#00E676`)
   - High Power Draw: High-Power Amber (`#FF9100`)
   - Fault / Critical Alert: Crimson Red (`#FF3B30`)

---

## 📜 Development & Code Rules

1. **Conditional Compilation Guards**:
   - Wrap iOS-only frameworks (e.g. `CarPlay`, `ActivityKit`) in `#if canImport(CarPlay)` or `#if os(iOS)` so the package compiles and runs unit tests cleanly via `swift test` on macOS command line.
   - Use custom `inlineTitleDisplayMode()` for `.navigationBarTitleDisplayMode(.inline)`.

2. **Concurrency Safety**:
   - Ensure classes conforming to `VehicleProfile` or protocol definitions maintain `Sendable` safety for Swift 6 mode.
   - Dispatch telemetry UI state updates strictly on `@MainActor` or `DispatchQueue.main`.

3. **UDS / CAN Message Decoding**:
   - Mercedes EQA 250 communicates using Unified Diagnostic Services (ISO 14229 Service `0x22` - ReadDataByIdentifier) over CAN ID `0x7E4` (BMS) and `0x7E0` (Powertrain).
   - Use `ISO15765Parser` to handle multi-line CAN frame assembly (`0x1N` First Frame, `0x2N` Consecutive Frame).

4. **Testing Requirement**:
   - Always run `swift test` after modifying PID decoders, ISO-TP frame parsers, or data models to ensure zero regressions.
