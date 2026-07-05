// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shredder",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Shredder"),
        .testTarget(name: "ShredderTests", dependencies: ["Shredder"])
    ]
)
