// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InnerTube",
    platforms: [.macOS(.v14)],
    products: [.library(name: "InnerTube", targets: ["InnerTube"])],
    dependencies: [.package(path: "../Auth")],
    targets: [
        .target(name: "InnerTube", dependencies: [.product(name: "Auth", package: "Auth")]),
        .testTarget(name: "InnerTubeTests", dependencies: ["InnerTube"], resources: [.copy("Fixtures")]),
    ]
)
