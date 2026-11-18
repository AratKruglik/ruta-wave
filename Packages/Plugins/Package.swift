// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plugins",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Plugins", targets: ["Plugins"])],
    dependencies: [.package(path: "../PlayerEngine"), .package(path: "../InnerTube"), .package(path: "../AppSettings")],
    targets: [
        .target(name: "Plugins", dependencies: [.product(name: "PlayerEngine", package: "PlayerEngine"), .product(name: "InnerTube", package: "InnerTube"), .product(name: "AppSettings", package: "AppSettings")]),
        .testTarget(name: "PluginsTests", dependencies: ["Plugins"]),
    ]
)
