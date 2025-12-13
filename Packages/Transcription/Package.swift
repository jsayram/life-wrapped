// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Transcription",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "Transcription",
            targets: ["Transcription"]
        ),
    ],
    dependencies: [
        .package(path: "../SharedModels"),
        .package(path: "../Storage"),
    ],
    targets: [
        .target(
            name: "Transcription",
            dependencies: ["SharedModels", "Storage"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TranscriptionTests",
            dependencies: ["Transcription"]
        ),
    ]
)
