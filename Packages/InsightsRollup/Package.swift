// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InsightsRollup",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11)
    ],
    products: [
        .library(
            name: "InsightsRollup",
            targets: ["InsightsRollup"]
        )
    ],
    dependencies: [
        .package(path: "../SharedModels"),
        .package(path: "../Storage")
    ],
    targets: [
        .target(
            name: "InsightsRollup",
            dependencies: ["SharedModels", "Storage"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "InsightsRollupTests",
            dependencies: ["InsightsRollup"]
        )
    ]
)
