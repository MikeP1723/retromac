// swift-tools-version:6.0
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "retromac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RetromacCore", targets: ["RetromacCore"]),
        .executable(name: "retromac", targets: ["retromac"]),
        .executable(name: "retromac-tool", targets: ["retromac-tool"]),
        .executable(name: "retromac-console", targets: ["retromac-console"]),
    ],
    targets: [
        .target(name: "RetromacCore", resources: [.process("Resources")]),
        .executableTarget(name: "retromac", dependencies: ["RetromacCore"]),
        .executableTarget(name: "retromac-tool", dependencies: ["RetromacCore"]),
        .executableTarget(name: "retromac-console", dependencies: ["RetromacCore"]),
        .testTarget(name: "RetromacCoreTests", dependencies: ["RetromacCore"]),
    ]
)
