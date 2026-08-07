# VoltLink Repository Instructions

Refer to [.gemini/rules.md](.gemini/rules.md) for full coding conventions, directory layout, and concurrency guidelines.

## Quick Summary
- **App Name**: VoltLink (Swift iOS & CarPlay OBD-II app)
- **Target Car**: Mercedes-Benz EQA 250 (2021)
- **Adapter**: Vgate iCar Pro 2S (BLE) & Generic ELM327 / Demo Mode
- **Testing**: `swift test`
- **Build**: `open Package.swift` or `xcodebuild -scheme VoltLinkEngine -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
