// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SystemKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SystemKit", targets: ["SystemKit"])],
    dependencies: [.package(path: "../PlayerEngine"), .package(path: "../AppSettings")],
    targets: [
        .target(name: "SystemKit", dependencies: [.product(name: "PlayerEngine", package: "PlayerEngine"), .product(name: "AppSettings", package: "AppSettings")]),
        .testTarget(name: "SystemKitTests", dependencies: ["SystemKit"]),
    ]
)
