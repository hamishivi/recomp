// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RecompCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "RecompCore", targets: ["RecompCore"])],
    targets: [
        .target(name: "RecompCore", path: "Recomp/Core"),
        .testTarget(name: "RecompCoreTests", dependencies: ["RecompCore"], path: "Tests/RecompCoreTests")
    ]
)
