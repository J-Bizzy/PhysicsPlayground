//
//  KinematicsSensing.swift
//  Physics Playground — Kinematics module
//
//  Feeds the real room's walls into the projectile physics: ARKit
//  plane detection turns vertical planes into RoomWalls rectangles the
//  balls can genuinely bounce off (the same restitution law as the
//  floor). Device-only and permission-gated, like the wind tunnel's
//  sensing — in the simulator the wall list simply stays empty.
//

import ARKit
import Foundation
import PhysicsCore
import simd

@MainActor
@Observable
final class KinematicsSensing {
    private let session = ARKitSession()
    private let planes = PlaneDetectionProvider(alignments: [.vertical])

    private(set) var isRunning = false
    private var wallsByAnchor: [UUID: RoomWalls.Wall] = [:]

    var walls: [RoomWalls.Wall] { Array(wallsByAnchor.values) }

    func start() async {
        guard PlaneDetectionProvider.isSupported else { return }
        do {
            try await session.run([planes])
            isRunning = true
        } catch {
            return
        }
        Task { await consume() }
    }

    func stop() {
        session.stop()
        isRunning = false
        wallsByAnchor = [:]
    }

    private func consume() async {
        for await update in planes.anchorUpdates {
            let anchor = update.anchor
            if update.event == .removed {
                wallsByAnchor[anchor.id] = nil
                continue
            }
            wallsByAnchor[anchor.id] = Self.wall(from: anchor)
        }
    }

    /// A plane anchor's extent rectangle in world space: the anchor's
    /// Y axis is the plane normal; the extent spans X (width) and Z
    /// (height) around the extent transform's center.
    private static func wall(from anchor: PlaneAnchor) -> RoomWalls.Wall {
        let originFromExtent = anchor.originFromAnchorTransform
            * anchor.geometry.extent.anchorFromExtentTransform
        let columns = originFromExtent.columns
        func axis(_ column: SIMD4<Float>) -> SIMD3<Double> {
            simd_normalize(SIMD3(Double(column.x), Double(column.y), Double(column.z)))
        }
        return RoomWalls.Wall(
            center: SIMD3(Double(columns.3.x), Double(columns.3.y), Double(columns.3.z)),
            normal: axis(columns.1),
            uAxis: axis(columns.0),
            vAxis: axis(columns.2),
            halfU: Double(anchor.geometry.extent.width) / 2,
            halfV: Double(anchor.geometry.extent.height) / 2)
    }
}
