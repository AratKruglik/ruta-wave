// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plugins",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Plugins", targets: ["Plugins"])],
    dependencies: [.package(path: "../PlayerEngine"), .package(path: "../InnerTube"), .package(path: "../AppSettings"), .package(path: "../SystemKit")],
    targets: [
        .target(name: "Plugins", dependencies: [.product(name: "PlayerEngine", package: "PlayerEngine"), .product(name: "InnerTube", package: "InnerTube"), .product(name: "AppSettings", package: "AppSettings"), .product(name: "SystemKit", package: "SystemKit")]),
        .testTarget(name: "PluginsTests", dependencies: ["Plugins", .product(name: "PlayerEngine", package: "PlayerEngine"), .product(name: "SystemKit", package: "SystemKit")]),
    ]
)
