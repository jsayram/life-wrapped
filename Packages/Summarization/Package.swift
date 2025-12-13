// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Summarization",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "Summarization",
            targets: ["Summarization"]
        ),
    ],
    dependencies: [
        .package(path: "../SharedModels"),
        .package(path: "../Storage"),
    ],
    targets: [
        .target(
            name: "Summarization",
            dependencies: ["SharedModels", "Storage"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "SummarizationTests",
            dependencies: ["Summarization"]
        ),
    ]
)
