//
//  WindTunnelSensing.swift
//  Physics Playground — Wind Tunnel module
//
//  Feeds the real room into the airflow: ARKit hand tracking turns the
//  user's hands and forearms into obstacle spheres, and scene
//  reconstruction turns nearby furniture and walls into coarse voxel
//  spheres — so the particle wind visibly parts around a raised hand or
//  a chair pushed into the test section.
//
//  Both providers are device-only (unsupported in the simulator) and
//  permission-gated; when unavailable the field simply stays empty.
//  What comes out of here is voxelised into the flow solver's SOLID
//  MASK, so a raised hand or a chair blocks the air exactly the way the
//  test body does — the pressure solve routes the flow around it and
//  sheds a wake behind. The only approximation is resolution: anything
//  smaller than a grid cell is rounded up to one.
//

import ARKit
import Foundation
import PhysicsCore
import simd

@MainActor
@Observable
final class WindTunnelSensing {
    private let session = ARKitSession()
    private let hands = HandTrackingProvider()
    private let sceneMesh = SceneReconstructionProvider()

    private(set) var isRunning = false
    private var handSpheres: [ObstacleField.Sphere] = []
    /// Voxelized room surfaces near the test section, per mesh anchor.
    private var meshSpheres: [UUID: [ObstacleField.Sphere]] = [:]

    /// Room voxels are only collected inside this box around the test
    /// section (world coordinates), and capped, so a whole scanned room
    /// never floods the field.
    private static let regionCenter = SIMD3<Double>(WindTunnelRenderer.sectionCenter)
    private static let regionHalfExtent = SIMD3<Double>(1.3, 0.7, 0.9)
    private static let voxelSize = 0.14
    private static let maxVoxelsPerAnchor = 40

    var field: ObstacleField {
        ObstacleField(spheres: handSpheres + meshSpheres.values.flatMap { $0 })
    }

    func start() async {
        var providers: [any DataProvider] = []
        if HandTrackingProvider.isSupported { providers.append(hands) }
        if SceneReconstructionProvider.isSupported { providers.append(sceneMesh) }
        guard !providers.isEmpty else { return }
        do {
            try await session.run(providers)
            isRunning = true
        } catch {
            return
        }
        if HandTrackingProvider.isSupported {
            Task { await consumeHands() }
        }
        if SceneReconstructionProvider.isSupported {
            Task { await consumeMeshes() }
        }
    }

    func stop() {
        session.stop()
        isRunning = false
        handSpheres = []
        meshSpheres = [:]
    }

    // MARK: Hands & forearms

    /// The joints that sketch a hand + forearm as spheres. Fingertips
    /// are small, the palm and forearm larger.
    private static let trackedJoints: [(HandSkeleton.JointName, Double)] = [
        (.wrist, 0.045), (.middleFingerKnuckle, 0.04),
        (.thumbTip, 0.02), (.indexFingerTip, 0.02), (.middleFingerTip, 0.02),
        (.ringFingerTip, 0.02), (.littleFingerTip, 0.02),
        (.forearmWrist, 0.05), (.forearmArm, 0.055),
    ]

    private func consumeHands() async {
        for await update in hands.anchorUpdates {
            guard update.event != .removed else { continue }
            var spheres: [ObstacleField.Sphere] = []
            for anchor in [hands.latestAnchors.leftHand, hands.latestAnchors.rightHand] {
                guard let anchor, anchor.isTracked, let skeleton = anchor.handSkeleton
                else { continue }
                for (name, radius) in Self.trackedJoints {
                    let joint = skeleton.joint(name)
                    guard joint.isTracked else { continue }
                    let world = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
                    let p = world.columns.3
                    spheres.append(.init(
                        center: SIMD3(Double(p.x), Double(p.y), Double(p.z)),
                        radius: radius))
                }
            }
            handSpheres = spheres
            _ = update  // per-update granularity is fine; latestAnchors carries both hands
        }
    }

    // MARK: Room surfaces → coarse voxel spheres

    private func consumeMeshes() async {
        for await update in sceneMesh.anchorUpdates {
            let anchor = update.anchor
            if update.event == .removed {
                meshSpheres[anchor.id] = nil
                continue
            }
            meshSpheres[anchor.id] = Self.voxels(from: anchor)
        }
    }

    private static func voxels(from anchor: MeshAnchor) -> [ObstacleField.Sphere] {
        let vertices = anchor.geometry.vertices
        guard vertices.format == .float3 else { return [] }
        let transform = anchor.originFromAnchorTransform
        let base = vertices.buffer.contents().advanced(by: vertices.offset)

        var occupied = Set<SIMD3<Int32>>()
        var spheres: [ObstacleField.Sphere] = []
        // Sampling every ~16th vertex keeps this cheap; mesh anchors
        // update rarely and voxels only need coarse coverage.
        for index in stride(from: 0, to: vertices.count, by: 16) {
            let raw = base.advanced(by: index * vertices.stride)
                .assumingMemoryBound(to: SIMD3<Float>.self).pointee
            let world4 = transform * SIMD4<Float>(raw.x, raw.y, raw.z, 1)
            let world = SIMD3(Double(world4.x), Double(world4.y), Double(world4.z))

            let offset = world - regionCenter
            guard abs(offset.x) < regionHalfExtent.x,
                  abs(offset.y) < regionHalfExtent.y,
                  abs(offset.z) < regionHalfExtent.z else { continue }

            let key = SIMD3<Int32>(
                Int32((world.x / voxelSize).rounded()),
                Int32((world.y / voxelSize).rounded()),
                Int32((world.z / voxelSize).rounded()))
            guard !occupied.contains(key) else { continue }
            occupied.insert(key)
            spheres.append(.init(
                center: SIMD3<Double>(key) * voxelSize,
                radius: voxelSize * 0.65))
            if spheres.count >= maxVoxelsPerAnchor { break }
        }
        return spheres
    }
}
