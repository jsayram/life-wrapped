// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Storage",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "Storage",
            targets: ["Storage"]
        ),
    ],
    dependencies: [
        .package(path: "../SharedModels"),
    ],
    targets: [
        .target(
            name: "Storage",
            dependencies: ["SharedModels"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "StorageTests",
            dependencies: ["Storage"]
        ),
    ]
)
