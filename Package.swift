// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmartCastKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "SmartCastKit",
            targets: ["SmartCastKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SmartCastKit",
            dependencies: [],
            path: "Sources/SmartCastKit"
        ),
        .testTarget(
            name: "SmartCastKitTests",
            dependencies: ["SmartCastKit"],
            path: "Tests/SmartCastKitTests"
        ),
    ]
)
