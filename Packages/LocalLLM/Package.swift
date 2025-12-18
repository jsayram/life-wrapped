// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalLLM",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "LocalLLM",
            targets: ["LocalLLM"]
        ),
    ],
    dependencies: [
        .package(path: "../SharedModels"),
        .package(url: "https://github.com/ShenghaiWang/SwiftLlama.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "LocalLLM",
            dependencies: [
                "SharedModels",
                "SwiftLlama",
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LocalLLMTests",
            dependencies: ["LocalLLM"]
        )
    ]
)
