// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PerfectAuthNet",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PerfectAuthNet", targets: ["PerfectAuthNet"]),
    ],
    targets: [
        .target(
            name: "PerfectAuthNet",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PerfectAuthNetTests",
            dependencies: ["PerfectAuthNet"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
