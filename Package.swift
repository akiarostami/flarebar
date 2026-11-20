// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flarebar",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "FlarebarCore"),
        .executableTarget(name: "Flarebar", dependencies: ["FlarebarCore"]),
        .testTarget(name: "FlarebarCoreTests", dependencies: ["FlarebarCore"]),
    ],
    swiftLanguageModes: [.v5]
)
