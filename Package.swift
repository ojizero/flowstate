// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FlowState",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "FlowCore", targets: ["FlowCore"]),
        .executable(name: "FlowState", targets: ["FlowState"]),
        .executable(name: "flowstate-cli", targets: ["FlowCLI"])
    ],
    targets: [
        .target(name: "FlowCore"),
        .executableTarget(name: "FlowState", dependencies: ["FlowCore"]),
        .executableTarget(name: "FlowCLI", dependencies: ["FlowCore"]),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"])
    ]
)
