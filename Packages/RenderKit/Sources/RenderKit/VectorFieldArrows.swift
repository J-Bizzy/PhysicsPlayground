//
//  VectorFieldArrows.swift
//  RenderKit
//
//  A pooled grid of arrow entities visualizing any vector field: each arrow
//  points along the field at its sample point, with length and brightness
//  encoding magnitude on a log scale (field magnitudes typically span many
//  orders of magnitude, so a linear map would leave most arrows invisible).
//
//  Pooling comes from EntityPool: the arrows are built once; updates only
//  touch transforms, visibility, and swaps between precomputed shared
//  materials — nothing allocates in the per-update path.
//

import Foundation
import RealityKit
import SwiftUI
import simd

@MainActor
public final class VectorFieldArrows {
    private struct ArrowParts {
        let shaft: ModelEntity
        let head: ModelEntity
    }

    private let pool: EntityPool<ArrowParts>

    /// Add this to the scene once; every arrow lives under it.
    public var root: Entity { pool.root }

    /// Brightness ramp: dim gray (weak) → bright yellow (strong).
    private let palette: [UnlitMaterial]
    private static let paletteSteps = 8

    public init(count: Int) {
        let palette = (0..<Self.paletteSteps).map { step in
            let t = CGFloat(step) / CGFloat(Self.paletteSteps - 1)
            let color = UIColor(
                red: 0.35 + 0.65 * t,
                green: 0.35 + 0.6 * t,
                blue: 0.4 - 0.25 * t,
                alpha: 1
            )
            return UnlitMaterial(color: color)
        }
        self.palette = palette

        // One shared mesh pair for every arrow keeps GPU memory flat.
        let shaftMesh = Primitives.cylinder(height: 0.035, radius: 0.0028)
        let headMesh = Primitives.cone(height: 0.015, radius: 0.007)

        pool = EntityPool(budget: count) { container in
            let shaft = ModelEntity(mesh: shaftMesh, materials: [palette[0]])
            shaft.position = [0, 0.0175, 0]
            let head = ModelEntity(mesh: headMesh, materials: [palette[0]])
            head.position = [0, 0.0425, 0]
            container.addChild(shaft)
            container.addChild(head)
            return ArrowParts(shaft: shaft, head: head)
        }
    }

    /// Re-aims the pool at the given field samples. `points`, `vectors`, and
    /// `hidden` are parallel arrays (extra pool slots are disabled; extra
    /// samples beyond the pool's budget are ignored).
    public func update(points: [SIMD3<Double>], vectors: [SIMD3<Double>], hidden: [Bool]) {
        var visible: [(slot: EntityPool<ArrowParts>.Slot, vector: SIMD3<Double>, logMagnitude: Double)] = []
        visible.reserveCapacity(pool.budget)

        for (index, slot) in pool.slots.enumerated() {
            guard index < points.count, index < vectors.count else {
                slot.entity.isEnabled = false
                continue
            }
            slot.entity.position = SIMD3<Float>(points[index])
            let magnitude = simd_length(vectors[index])
            if (index < hidden.count && hidden[index]) || magnitude < 1e-9 {
                slot.entity.isEnabled = false
                continue
            }
            slot.entity.isEnabled = true
            visible.append((slot, vectors[index], log10(magnitude)))
        }

        let logs = visible.map(\.logMagnitude)
        let lo = logs.min() ?? 0
        let hi = logs.max() ?? 1
        let range = max(hi - lo, 1e-9)

        for (slot, vector, logMagnitude) in visible {
            let t = Float((logMagnitude - lo) / range)
            let direction = simd_normalize(SIMD3<Float>(vector))
            slot.entity.orientation = Self.rotationFromYAxis(to: direction)
            slot.entity.scale = SIMD3<Float>(repeating: 0.5 + 1.5 * t)
            let material = palette[min(Int(t * Float(Self.paletteSteps)), Self.paletteSteps - 1)]
            slot.payload.shaft.model?.materials = [material]
            slot.payload.head.model?.materials = [material]
        }
    }

    public func hideAll() {
        pool.hideAll()
    }

    /// Rotation taking the arrow's rest axis (+Y) to `direction`; the
    /// antiparallel guard lives in `RenderKit.rotation(from:to:)`.
    public static func rotationFromYAxis(to direction: SIMD3<Float>) -> simd_quatf {
        rotation(from: [0, 1, 0], to: direction)
    }
}
