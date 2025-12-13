// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AudioCapture",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AudioCapture",
            targets: ["AudioCapture"]
        )
    ],
    dependencies: [
        .package(path: "../SharedModels")
    ],
    targets: [
        .target(
            name: "AudioCapture",
            dependencies: ["SharedModels"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AudioCaptureTests",
            dependencies: ["AudioCapture"]
        )
    ]
)
