// swift-tools-version:6.2
// RenderKit — Physics Playground's shared RealityKit rendering primitives.
//
// Sits between PhysicsCore (pure math, which it may import) and the app's
// modules (which import it). The dependency only points this way: PhysicsCore
// never knows RenderKit exists.
//
// visionOS-only, unlike PhysicsCore: these files use RealityKit manipulation
// and UIKit colors, and their correctness is visual — they're verified by
// building and running the app, not by `swift test` on the Mac.

import PackageDescription

let package = Package(
    name: "RenderKit",
    platforms: [
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "RenderKit",
            targets: ["RenderKit"]),
    ],
    dependencies: [
        .package(path: "../PhysicsCore"),
    ],
    targets: [
        .target(
            name: "RenderKit",
            dependencies: ["PhysicsCore"]),
    ]
)
