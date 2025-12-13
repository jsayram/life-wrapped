// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Backup",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "Backup",
            targets: ["Backup"]
        ),
    ],
    dependencies: [
        .package(path: "../SharedModels"),
        .package(path: "../Storage"),
    ],
    targets: [
        .target(
            name: "Backup",
            dependencies: ["SharedModels", "Storage"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "BackupTests",
            dependencies: ["Backup"]
        ),
    ]
)
