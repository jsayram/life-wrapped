// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Insights",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "Insights",
            targets: ["Insights"]
        ),
    ],
    dependencies: [
        .package(path: "../SharedModels"),
        .package(path: "../Storage"),
    ],
    targets: [
        .target(
            name: "Insights",
            dependencies: ["SharedModels", "Storage"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "InsightsTests",
            dependencies: ["Insights"]
        ),
    ]
)
