# VoltLink Repository Instructions

Refer to [.gemini/rules.md](.gemini/rules.md) for full coding conventions, directory layout, and concurrency guidelines.

## Quick Summary
- **App Name**: VoltLink (Swift iOS & CarPlay OBD-II app)
- **Target Car**: Mercedes-Benz EQA 250 (2021)
- **Adapter**: Vgate iCar Pro 2S (BLE) & Generic ELM327 / Demo Mode
- **Testing**: `swift test`
- **Build**: `open VoltLink.xcodeproj` or `xcodebuild -scheme VoltLink -destination 'platform=iOS Simulator,name=iPhone 17'`
- **Git Commits**: Always follow Conventional Commits format with explicit scope (`type(scope): summary`) and a detailed multiline explanation in the commit body (e.g. `feat(telemetry): ...`, `fix(location): ...`).
