// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlayerEngine",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PlayerEngine", targets: ["PlayerEngine"])],
    dependencies: [.package(path: "../Auth")],
    targets: [
        .target(
            name: "PlayerEngine",
            dependencies: [.product(name: "Auth", package: "Auth")],
            resources: [.copy("Resources/bridge.js"), .copy("Resources/nowplaying.js")]
        ),
        .testTarget(name: "PlayerEngineTests", dependencies: ["PlayerEngine"], resources: [.copy("Fixtures")]),
    ]
)
