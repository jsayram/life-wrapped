// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WidgetCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "WidgetCore",
            targets: ["WidgetCore"]),
    ],
    dependencies: [
        .package(path: "../SharedModels"),
    ],
    targets: [
        .target(
            name: "WidgetCore",
            dependencies: ["SharedModels"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "WidgetCoreTests",
            dependencies: ["WidgetCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
