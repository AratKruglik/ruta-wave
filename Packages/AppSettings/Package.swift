// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppSettings",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AppSettings", targets: ["AppSettings"])],
    dependencies: [],
    targets: [
        .target(name: "AppSettings", dependencies: []),
        .testTarget(name: "AppSettingsTests", dependencies: ["AppSettings"]),
    ]
)
