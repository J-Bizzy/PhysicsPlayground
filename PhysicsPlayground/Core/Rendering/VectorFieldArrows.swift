//
//  VectorFieldArrows.swift
//  Physics Playground — Core kernel
//
//  A pooled grid of arrow entities visualizing any vector field: each arrow
//  points along the field at its sample point, with length and brightness
//  encoding magnitude on a log scale (field magnitudes typically span many
//  orders of magnitude, so a linear map would leave most arrows invisible).
//
//  The pool is built once; updates only touch transforms, visibility, and
//  swaps between precomputed shared materials — nothing allocates in the
//  per-update path.
//

import Foundation
import RealityKit
import SwiftUI
import simd

@MainActor
final class VectorFieldArrows {
    let root = Entity()

    private struct Slot {
        let container: Entity
        let shaft: ModelEntity
        let head: ModelEntity
    }

    private var slots: [Slot] = []

    /// Brightness ramp: dim gray (weak) → bright yellow (strong).
    private let palette: [UnlitMaterial]
    private static let paletteSteps = 8

    init(count: Int) {
        palette = (0..<Self.paletteSteps).map { step in
            let t = CGFloat(step) / CGFloat(Self.paletteSteps - 1)
            let color = UIColor(
                red: 0.35 + 0.65 * t,
                green: 0.35 + 0.6 * t,
                blue: 0.4 - 0.25 * t,
                alpha: 1
            )
            return UnlitMaterial(color: color)
        }

        // One shared mesh pair for every arrow keeps GPU memory flat.
        let shaftMesh = MeshResource.generateCylinder(height: 0.035, radius: 0.0028)
        let headMesh = MeshResource.generateCone(height: 0.015, radius: 0.007)

        slots = (0..<count).map { _ in
            let shaft = ModelEntity(mesh: shaftMesh, materials: [palette[0]])
            shaft.position = [0, 0.0175, 0]
            let head = ModelEntity(mesh: headMesh, materials: [palette[0]])
            head.position = [0, 0.0425, 0]

            let container = Entity()
            container.addChild(shaft)
            container.addChild(head)
            container.isEnabled = false
            root.addChild(container)
            return Slot(container: container, shaft: shaft, head: head)
        }
    }

    /// Re-aims the pool at the given field samples. `points`, `vectors`, and
    /// `hidden` are parallel arrays (extra pool slots are disabled; extra
    /// samples beyond the pool size are ignored).
    func update(points: [SIMD3<Double>], vectors: [SIMD3<Double>], hidden: [Bool]) {
        var visible: [(slot: Slot, vector: SIMD3<Double>, logMagnitude: Double)] = []
        visible.reserveCapacity(slots.count)

        for (index, slot) in slots.enumerated() {
            guard index < points.count, index < vectors.count else {
                slot.container.isEnabled = false
                continue
            }
            slot.container.position = SIMD3<Float>(points[index])
            let magnitude = simd_length(vectors[index])
            if (index < hidden.count && hidden[index]) || magnitude < 1e-9 {
                slot.container.isEnabled = false
                continue
            }
            slot.container.isEnabled = true
            visible.append((slot, vectors[index], log10(magnitude)))
        }

        let logs = visible.map(\.logMagnitude)
        let lo = logs.min() ?? 0
        let hi = logs.max() ?? 1
        let range = max(hi - lo, 1e-9)

        for (slot, vector, logMagnitude) in visible {
            let t = Float((logMagnitude - lo) / range)
            let direction = simd_normalize(SIMD3<Float>(vector))
            slot.container.orientation = Self.rotationFromYAxis(to: direction)
            slot.container.scale = SIMD3<Float>(repeating: 0.5 + 1.5 * t)
            let material = palette[min(Int(t * Float(Self.paletteSteps)), Self.paletteSteps - 1)]
            slot.shaft.model?.materials = [material]
            slot.head.model?.materials = [material]
        }
    }

    func hideAll() {
        for slot in slots { slot.container.isEnabled = false }
    }

    /// Rotation taking the arrow's rest axis (+Y) to `direction`.
    /// simd_quatf(from:to:) is undefined for exactly opposite vectors, so the
    /// antiparallel case gets an explicit 180° flip.
    static func rotationFromYAxis(to direction: SIMD3<Float>) -> simd_quatf {
        let up = SIMD3<Float>(0, 1, 0)
        if simd_dot(up, direction) < -0.9999 {
            return simd_quatf(angle: .pi, axis: [1, 0, 0])
        }
        return simd_quatf(from: up, to: direction)
    }
}
