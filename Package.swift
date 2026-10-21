// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoltLink",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "VoltLinkEngine",
            targets: ["VoltLinkEngine"]
        ),
        .executable(
            name: "EQAProbe",
            targets: ["EQAProbe"]
        ),
        .executable(
            name: "VoltLinkCLI",
            targets: ["VoltLinkCLI"]
        ),
        .executable(
            name: "SyncVehicleData",
            targets: ["SyncVehicleData"]
        ),
    ],
    targets: [
        .target(
            name: "VoltLinkEngine",
            path: ".",
            exclude: [
                "README.md",
                "LICENSE",
                "CLAUDE.md",
                "INSTRUCTIONS.md",
                "AGENTS.md",
                "ruvector.db",
                "skills-lock.json",
                "build",
                "docs",
                "knowledge",
                "scratch",
                "Tools",
                "Tests",
                "UITests",
                "Widgets",
                "App/Info.plist",
                "App/Assets.xcassets",
                "App/VoltLink.entitlements",
                "App/PrivacyInfo.xcprivacy",
                "App/Localizable.xcstrings",
                "opencode.json",
            ],
            sources: [
                "App",
                "CarPlay",
                "Core",
                "Data/Models",
                "Data/Repositories",
                "Services",
                "UI",
            ],
            resources: [
                .process("Data/Seed/dtc_definitions.json"),
                .process("Data/Seed/wal33d_dtc.json"),
                .process("Data/Seed/vehicle_catalog.json"),
                .copy("Data/Seed/abrp_pids"),
            ]
        ),
        .testTarget(
            name: "VoltLinkTests",
            dependencies: ["VoltLinkEngine"],
            path: "Tests"
        ),
        .executableTarget(
            name: "EQAProbe",
            dependencies: ["VoltLinkEngine"],
            path: "Tools/EQAProbe"
        ),
        .executableTarget(
            name: "VoltLinkCLI",
            dependencies: ["VoltLinkEngine"],
            path: "Tools/VoltLinkCLI"
        ),
        .executableTarget(
            name: "SyncVehicleData",
            dependencies: ["VoltLinkEngine"],
            path: "Tools/SyncVehicleData"
        ),
    ],
    // Enforce the concurrency model the docs already claim. Swift 5 mode let
    // non-Sendable state cross adapter callbacks and timers without diagnostics.
    swiftLanguageModes: [.v6]
)
