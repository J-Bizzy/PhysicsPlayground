//
//  WaveMediumRenderer.swift
//  Physics Playground — Elastic Field (Springs module)
//
//  Renders the membrane as a live shaded surface: the height field is
//  triangulated every frame with real per-vertex normals, so room
//  light rakes across the ripples and the 3-D wave shape reads from
//  any angle. Triangles are split into height bands (trough blue →
//  rest teal → crest red), a glowing rim traces the boundary, and the
//  point in your hand wears a halo. All the vertex math runs on a
//  GeometryPipeline worker; the main thread only uploads meshes.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class WaveMediumRenderer {
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    static let surfaceName = "sheet-surface"

    private static let bandCount = 13
    /// Height (m) spanned by the color ramp, ± this.
    private static let bandSpan: Float = 0.14
    private var bandEntities: [ModelEntity] = []
    private let rimEntity = ModelEntity()
    private let rimMaterial: UnlitMaterial = {
        var m = UnlitMaterial(color: UIColor(red: 0.3, green: 0.85, blue: 0.85, alpha: 1))
        m.blending = .transparent(opacity: 0.85)
        return m
    }()
    private let heldHalo = ModelEntity()
    private var surfacePipeline: GeometryPipeline<SurfaceJob, SurfaceResult>?

    init() {
        // Band materials: a fine deep-blue → teal → red ramp so the
        // height field reads as a smooth topographic heatmap, lit
        // (normals reveal the 3-D shape) with a glow toward the
        // extremes so big crests and troughs read as energy.
        for index in 0..<Self.bandCount {
            let t = Float(index) / Float(Self.bandCount - 1)   // 0…1
            let color = Self.rampColor(t)
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.roughness = 0.3
            material.metallic = 0.0
            material.faceCulling = .none
            let energy = abs(t - 0.5) * 2      // 0 at rest, 1 at extremes
            material.emissiveColor = .init(color: color)
            material.emissiveIntensity = 0.15 + 0.5 * energy
            let entity = ModelEntity()
            entity.model = ModelComponent(mesh: .generateSphere(radius: 0.0001),
                                          materials: [material])
            root.addChild(entity)
            bandEntities.append(entity)
        }
        root.addChild(rimEntity)

        // The grab volume: an invisible slab over the sheet's footprint,
        // tall enough to catch a hand reaching to any crest or trough.
        let half = Float(WaveMediumModel.halfSide)
        let collider = ModelEntity()
        collider.name = Self.surfaceName
        collider.position = SIMD3<Float>(WaveMediumModel.center)
        collider.components.set(InputTargetComponent())
        collider.components.set(CollisionComponent(shapes: [
            .generateBox(width: half * 2 + 0.08,
                         height: Float(WaveMediumModel.pluckClamp) * 2 + 0.1,
                         depth: half * 2 + 0.08)
        ]))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Elastic membrane. Reach in, pull any point, and let go to send a wave."
        collider.components.set(accessibility)
        root.addChild(collider)

        // The held-point halo.
        var haloMaterial = UnlitMaterial(color: .white)
        haloMaterial.blending = .transparent(opacity: 0.5)
        heldHalo.model = ModelComponent(
            mesh: .generateSphere(radius: 0.03), materials: [haloMaterial])
        heldHalo.isEnabled = false
        root.addChild(heldHalo)

        surfacePipeline = GeometryPipeline(
            compute: { Self.computeSurface($0) },
            apply: { [weak self] in self?.applySurface($0) }
        )
    }

    /// A perceptual blue→teal→red ramp for a signed height field.
    private nonisolated static func rampColor(_ t: Float) -> UIColor {
        // Control stops, evenly spaced across 0…1.
        let stops: [(Float, Float, Float)] = [
            (0.10, 0.30, 0.95),   // deep trough — blue
            (0.15, 0.55, 0.95),
            (0.20, 0.78, 0.85),
            (0.15, 0.78, 0.68),   // rest — teal
            (0.55, 0.85, 0.4),
            (0.98, 0.72, 0.3),    // crest — amber
            (1.0, 0.38, 0.3),     // high crest — red
        ]
        let scaled = min(max(t, 0), 1) * Float(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        let f = scaled - Float(i)
        let a = stops[i], b = stops[i + 1]
        return UIColor(red: CGFloat(a.0 + (b.0 - a.0) * f),
                       green: CGFloat(a.1 + (b.1 - a.1) * f),
                       blue: CGFloat(a.2 + (b.2 - a.2) * f), alpha: 1)
    }

    // MARK: Per-frame

    func tick(dt: Double, model: WaveMediumModel) {
        model.step(dt: dt)

        let sheet = model.sheet
        surfacePipeline?.submit(SurfaceJob(
            heights: sheet.height.map { Float($0) },
            n: sheet.n, spacing: Float(WaveMediumModel.spacing),
            center: SIMD3<Float>(WaveMediumModel.center)))

        if let node = model.heldNode {
            heldHalo.isEnabled = true
            heldHalo.position = SIMD3<Float>(model.world(i: node.i, j: node.j))
        } else {
            heldHalo.isEnabled = false
        }
    }

    // MARK: Surface build (worker)

    private nonisolated struct SurfaceJob: Sendable {
        var heights: [Float]
        var n: Int
        var spacing: Float
        var center: SIMD3<Float>
    }

    private nonisolated struct SurfaceResult: Sendable {
        var positions: [[SIMD3<Float>]]   // per band
        var normals: [[SIMD3<Float>]]
        var rim: [SIMD3<Float>]
    }

    private nonisolated static func computeSurface(_ job: SurfaceJob) -> SurfaceResult {
        let n = job.n
        let a = job.spacing
        let half = Float(n - 1) * a / 2
        let h = job.heights

        @inline(__always) func height(_ i: Int, _ j: Int) -> Float {
            h[j * n + i]
        }
        @inline(__always) func position(_ i: Int, _ j: Int) -> SIMD3<Float> {
            job.center + SIMD3(Float(i) * a - half, height(i, j), Float(j) * a - half)
        }
        // Surface normal from the height gradient (clamped at edges).
        func normal(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let il = max(i - 1, 0), ir = min(i + 1, n - 1)
            let jl = max(j - 1, 0), jr = min(j + 1, n - 1)
            let dhdx = (height(ir, j) - height(il, j)) / (Float(ir - il) * a)
            let dhdz = (height(i, jr) - height(i, jl)) / (Float(jr - jl) * a)
            return simd_normalize(SIMD3(-dhdx, 1, -dhdz))
        }

        // Even thresholds across ±bandSpan → bandCount contour bands.
        func band(_ y: Float) -> Int {
            let f = (y + bandSpan) / (2 * bandSpan)   // 0…1 across the ramp
            return min(max(Int(f * Float(bandCount)), 0), bandCount - 1)
        }

        var positions = Array(repeating: [SIMD3<Float>](), count: bandCount)
        var normals = Array(repeating: [SIMD3<Float>](), count: bandCount)

        func emit(_ i0: Int, _ j0: Int, _ i1: Int, _ j1: Int, _ i2: Int, _ j2: Int) {
            let avg = (height(i0, j0) + height(i1, j1) + height(i2, j2)) / 3
            let b = band(avg)
            positions[b].append(position(i0, j0))
            positions[b].append(position(i1, j1))
            positions[b].append(position(i2, j2))
            normals[b].append(normal(i0, j0))
            normals[b].append(normal(i1, j1))
            normals[b].append(normal(i2, j2))
        }

        for j in 0..<(n - 1) {
            for i in 0..<(n - 1) {
                emit(i, j, i + 1, j, i + 1, j + 1)
                emit(i, j, i + 1, j + 1, i, j + 1)
            }
        }

        // Rim loop for the boundary tube.
        var rim: [SIMD3<Float>] = []
        for i in 0..<n { rim.append(position(i, 0)) }
        for j in 1..<n { rim.append(position(n - 1, j)) }
        for i in stride(from: n - 2, through: 0, by: -1) { rim.append(position(i, n - 1)) }
        for j in stride(from: n - 2, through: 0, by: -1) { rim.append(position(0, j)) }

        return SurfaceResult(positions: positions, normals: normals, rim: rim)
    }

    private func applySurface(_ result: SurfaceResult) {
        for (index, entity) in bandEntities.enumerated() {
            let positions = result.positions[index]
            guard positions.count >= 3 else {
                entity.isEnabled = false
                continue
            }
            entity.isEnabled = true
            var descriptor = MeshDescriptor(name: "band")
            descriptor.positions = MeshBuffer(positions)
            descriptor.normals = MeshBuffer(result.normals[index])
            descriptor.primitives = .triangles(Array(0..<UInt32(positions.count)))
            if let mesh = try? MeshResource.generate(from: [descriptor]) {
                entity.model?.mesh = mesh
            }
        }
        if result.rim.count >= 2,
           let mesh = TubeMesh.tube(lines: [result.rim], radius: 0.004, sides: 4) {
            rimEntity.model = ModelComponent(mesh: mesh, materials: [rimMaterial])
        }
    }
}
