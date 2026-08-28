// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "deezdown",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DeezDownKit", targets: ["DeezDownKit"]),
        .executable(name: "deezdown", targets: ["deezdown"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "DeezDownKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "deezdown",
            dependencies: [
                "DeezDownKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DeezDownKitTests",
            dependencies: ["DeezDownKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
