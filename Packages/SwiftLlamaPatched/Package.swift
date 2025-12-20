// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftLlama",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "SwiftLlama", targets: ["SwiftLlama"]),
    ],
    dependencies: [
        // Use known-good llama.cpp commit for headers; binary xcframework provides runtime
        .package(url: "https://github.com/ggerganov/llama.cpp.git", revision: "b6d6c5289f1c9c677657c380591201ddb210b649"),
    ],
    targets: [
        .target(
            name: "SwiftLlama",
            dependencies: [
                "LlamaFramework",
                .product(name: "llama", package: "llama.cpp"),
            ]
        ),
        .testTarget(
            name: "SwiftLlamaTests",
            dependencies: ["SwiftLlama"]
        ),
        // Local xcframework unpacked from llama.cpp release b7486 for Llama 3.2 tokenizer support
        .binaryTarget(
            name: "LlamaFramework",
            path: "llama.xcframework"
        )
    ]
)
