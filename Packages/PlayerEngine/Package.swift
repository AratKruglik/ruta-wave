// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlayerEngine",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PlayerEngine", targets: ["PlayerEngine"])],
    dependencies: [.package(path: "../Auth")],
    targets: [
        .target(name: "PlayerEngine", dependencies: [.product(name: "Auth", package: "Auth")]),
        .testTarget(name: "PlayerEngineTests", dependencies: ["PlayerEngine"]),
    ]
)
