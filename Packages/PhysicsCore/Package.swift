// swift-tools-version:6.2
// PhysicsCore — the pure-math layer of Physics Playground.
//
// Deliberately links NOTHING beyond the standard library and simd: no
// RealityKit, no SwiftUI. That makes the layering compiler-enforced, and it
// means the test target builds and runs natively on the Mac (`swift test`),
// with no visionOS simulator in the loop.

import PackageDescription

let package = Package(
    name: "PhysicsCore",
    platforms: [
        .visionOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "PhysicsCore",
            targets: ["PhysicsCore"]),
    ],
    targets: [
        .target(
            name: "PhysicsCore"),
        .testTarget(
            name: "PhysicsCoreTests",
            dependencies: ["PhysicsCore"]),
    ]
)
