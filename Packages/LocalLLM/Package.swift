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
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.29.1"),
        // Pinned to the exact commit the app is built and tested with. Following "main" would pull
        // in mlx-swift-lm 3.x, which changes its API, the next time packages are resolved.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", revision: "d9f46e3a1fe715d01304372089aba5f39c585327"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.0")
    ],
    targets: [
        .target(
            name: "LocalLLM",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers")
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
