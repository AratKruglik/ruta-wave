// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Auth",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Auth", targets: ["Auth"])],
    dependencies: [],
    targets: [
        .target(name: "Auth", dependencies: []),
        .testTarget(name: "AuthTests", dependencies: ["Auth"]),
    ]
)
