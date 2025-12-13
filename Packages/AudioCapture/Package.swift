// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AudioCapture",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "AudioCapture",
            targets: ["AudioCapture"]
        ),
    ],
    dependencies: [
        .package(path: "../SharedModels"),
        .package(path: "../Storage"),
    ],
    targets: [
        .target(
            name: "AudioCapture",
            dependencies: ["SharedModels", "Storage"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "AudioCaptureTests",
            dependencies: ["AudioCapture"]
        ),
    ]
)
