# VoltLink

Native OBD-II diagnostics and live EV telemetry for **iOS / Apple CarPlay** and
**Android / Android Auto**. VoltLink talks to a BLE adapter (Vgate iCar Pro 2S or any
ELM327-compatible dongle), decodes UDS/SAE J1979 telemetry for the
**Mercedes-Benz EQA 250 (2021)** and other EV profiles, and includes a
physics-based demo mode that needs no hardware.

## Repository layout

This is a two-project repository: each platform owns its sources, build tooling,
and tests, and the projects do not share build files.

```text
.
├── ios/        # SwiftUI + CarPlay app, VoltLink.xcodeproj, SwiftPM tests, OKF knowledge bundle
└── android/    # Kotlin + Compose app, Gradle build, unit/UI tests, OKF knowledge bundle
```

| Project | Status | Entry point |
| --- | --- | --- |
| iOS / CarPlay | Shipping (Swift 6, iOS 17+, Xcode 16) | [`ios/README.md`](ios/README.md) |
| Android / Android Auto | Shipping (Kotlin + Compose, min SDK 29) | [`android/README.md`](android/README.md) |

## Quick start (iOS)

```bash
cd ios
swift test                     # engine + app logic on macOS
open VoltLink.xcodeproj        # build/run the iOS & CarPlay app (Cmd+R)
```

Architecture, features, screenshots, simulator/CarPlay setup, and packaging
instructions live in [`ios/README.md`](ios/README.md).

## Quick start (Android)

```bash
cd android
./gradlew assembleDebug        # build the debug APK
./gradlew testDebugUnitTest    # JVM unit tests (engine, profiles, layouts)
```

Architecture, feature parity with iOS, the Android Auto pane, and the emulator
setup live in [`android/README.md`](android/README.md).

## Repository-wide files

- [`AGENTS.md`](AGENTS.md) — coding agents' guide for the whole repo (both projects).
- [`.gitignore`](.gitignore), [`LICENSE`](LICENSE).
- [`ios/knowledge/`](ios/knowledge/index.md) and [`android/knowledge/`](android/knowledge/index.md)
  — the two Open Knowledge Format bundles for the telemetry/diagnostics domain, one
  per project. They are generated from each project's own sources and are not shared.

<img src="ios/docs/assets/telemetry.png" width="240" alt="VoltLink live telemetry dashboard" />
