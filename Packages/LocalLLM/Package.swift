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
        // Patched SwiftLlama using llama.cpp b7486 XCFramework for Llama 3.2 tokenizer compatibility
        .package(path: "../SwiftLlamaPatched"),
    ],
    targets: [
        .target(
            name: "LocalLLM",
            dependencies: [
                "SharedModels",
                .product(name: "SwiftLlama", package: "SwiftLlamaPatched"),
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
