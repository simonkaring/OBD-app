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
        )
    ],
    targets: [
        .target(
            name: "VoltLinkEngine",
            path: ".",
            exclude: [
                "README.md",
                "LICENSE",
                "App/Info.plist"
            ],
            sources: [
                "App",
                "CarPlay",
                "Core",
                "Data/Models",
                "Data/Repositories",
                "Services",
                "UI",
                "Widgets"
            ],
            resources: [
                .process("Data/Seed/dtc_definitions.json")
            ]
        ),
        .testTarget(
            name: "VoltLinkTests",
            dependencies: ["VoltLinkEngine"],
            path: "Tests"
        )
    ]
)
