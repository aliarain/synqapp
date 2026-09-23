// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SynqCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SynqCore", targets: ["SynqCore"])],
    targets: [
        .target(name: "SynqCore"),
        .testTarget(name: "SynqCoreTests", dependencies: ["SynqCore"]),
    ]
)
