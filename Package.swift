// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HiveAxylSDK",
    platforms: [
        .iOS(.v14),
        .macOS(.v12),
    ],
    products: [
        .library(name: "HiveAxylSDK", targets: ["HiveAxylSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.30.0"),
    ],
    targets: [
        .target(
            name: "HiveAxylSDK",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources",
            sources: ["HiveAxylSDK", "Gen"]
        ),
        .testTarget(
            name: "HiveAxylSDKTests",
            dependencies: [
                "HiveAxylSDK",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Tests/HiveAxylSDKTests"
        ),
    ]
)
