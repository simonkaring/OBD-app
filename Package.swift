// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoltLink",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
        )
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
                "scratch",
                "Tools",
                "Tests",
                "App/Info.plist",
                "App/Assets.xcassets",
                "App/VoltLink.entitlements"
            ],
            sources: [
                "App",
                "CarPlay",
                "Core",
                "Data/Models",
                "Data/Repositories",
                "Services",
                "UI"
            ],
            resources: [
                .process("Data/Seed/dtc_definitions.json"),
                .process("Data/Seed/vehicle_catalog.json"),
                .copy("Data/Seed/abrp_pids")
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
        )
    ]
)
