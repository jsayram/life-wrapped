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
        // TODO: Add llama.cpp Swift wrapper in Phase 2A.2
        // .package(url: "https://github.com/ggerganov/llama.cpp.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "LocalLLM",
            dependencies: [
                "SharedModels",
                // TODO: Add llama dependency when wrapper is ready
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
