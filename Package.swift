// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Flowstate",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "FlowCore", targets: ["FlowCore"]),
        .executable(name: "Flowstate", targets: ["Flowstate"]),
        .executable(name: "flowstate-cli", targets: ["FlowCLI"])
    ],
    targets: [
        .target(name: "FlowCore"),
        .executableTarget(name: "Flowstate", dependencies: ["FlowCore"]),
        .executableTarget(name: "FlowCLI", dependencies: ["FlowCore"]),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"])
    ]
)
