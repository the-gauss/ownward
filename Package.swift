// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Ownward",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "OwnwardCore", targets: ["OwnwardCore"]),
        .library(name: "OwnwardServices", targets: ["OwnwardServices"]),
        .executable(name: "Ownward", targets: ["OwnwardApp"]),
    ],
    targets: [
        .target(name: "OwnwardCore"),
        .target(name: "OwnwardServices", dependencies: ["OwnwardCore"]),
        .executableTarget(
            name: "OwnwardApp",
            dependencies: ["OwnwardCore", "OwnwardServices"],
            exclude: ["Resources/Brand/Ownward.icns"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "OwnwardCoreTests", dependencies: ["OwnwardCore"]),
        .testTarget(name: "OwnwardServicesTests", dependencies: ["OwnwardServices", "OwnwardCore"]),
    ]
)
