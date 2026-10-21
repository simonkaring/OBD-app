# VoltLink Repository Instructions

Refer to [.gemini/rules.md](.gemini/rules.md) for full coding conventions, directory layout, and concurrency guidelines.

## Quick Summary
- **App Name**: VoltLink (Swift iOS & CarPlay OBD-II app)
- **Target Car**: Mercedes-Benz EQA 250 (2021)
- **Adapter**: Vgate iCar Pro 2S (BLE) & Generic ELM327 / Demo Mode
- **Testing**: `swift test` (228 unit tests) and `xcodebuild test -scheme VoltLink -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VoltLinkUITests`
- **Build**: `open VoltLink.xcodeproj` or `xcodebuild -scheme VoltLink -destination 'platform=iOS Simulator,name=iPhone 17'`
- **Project generation**: `python3 scratch/make_xcodeproj.py` (do not hand-edit `project.pbxproj`; it also emits the `VoltLinkWidgets` extension target and embeds it in the app)
- **Widgets / Live Activities**: app and extension share data through the `group.com.simonkaring.voltlink` app group, which must be enabled for both bundle identifiers in the developer portal for signed builds
- **Formatting**: `swift format lint --strict --recursive --configuration .swift-format Package.swift App CarPlay Core Data Services UI Widgets Tests UITests Tools`
- **Git Commits**: Always follow Conventional Commits format with explicit scope (`type(scope): summary`) and a detailed multiline explanation in the commit body (e.g. `feat(telemetry): ...`, `fix(location): ...`).
