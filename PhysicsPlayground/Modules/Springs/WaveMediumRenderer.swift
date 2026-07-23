//
//  WaveMediumRenderer.swift
//  Physics Playground — Elastic Field (Springs module)
//
//  Renders the membrane as a live shaded surface: the height field is
//  triangulated every frame with real per-vertex normals, so room
//  light rakes across the ripples and the 3-D wave shape reads from
//  any angle. Colour is a smooth topographic heatmap — each vertex
//  carries a texture coordinate equal to its height, and a gradient
//  texture (deep-blue trough → teal rest → red crest) is sampled
//  per-pixel, so the colour flows continuously instead of stepping in
//  jagged bands. A glowing rim traces the boundary; the point in your
//  hand wears a halo. The vertex math runs on a GeometryPipeline
//  worker; the main thread only uploads the mesh.
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

    /// Height (m) the colour ramp spans, ±this.
    private static let heightSpan: Float = 0.14

    private let surfaceEntity = ModelEntity()
    private let rimEntity = ModelEntity()
    private let rimMaterial: UnlitMaterial = {
        var m = UnlitMaterial(color: UIColor(red: 0.3, green: 0.85, blue: 0.85, alpha: 1))
        m.blending = .transparent(opacity: 0.85)
        return m
    }()
    private let heldHalo = ModelEntity()
    private var surfacePipeline: GeometryPipeline<SurfaceJob, SurfaceResult>?

    init() {
        // One lit surface with a gradient-texture heatmap: baseColor
        // (and a gentle emissive) are sampled along the ramp by each
        // vertex's height, so the colour is smooth and the normals
        // still let room light reveal the 3-D shape.
        var material = PhysicallyBasedMaterial()
        if let texture = Self.gradientTexture() {
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.emissiveColor = .init(color: .white, texture: .init(texture))
            material.emissiveIntensity = 0.45
        } else {
            material.baseColor = .init(tint: UIColor(red: 0.15, green: 0.78, blue: 0.68, alpha: 1))
        }
        material.roughness = 0.28
        material.metallic = 0.0
        material.faceCulling = .none
        surfaceEntity.model = ModelComponent(
            mesh: .generateSphere(radius: 0.0001), materials: [material])
        root.addChild(surfaceEntity)
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
    private nonisolated static func rampColor(_ t: Float) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
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
        return (CGFloat(a.0 + (b.0 - a.0) * f),
                CGFloat(a.1 + (b.1 - a.1) * f),
                CGFloat(a.2 + (b.2 - a.2) * f))
    }

    /// A 256×1 gradient baked from the ramp, sampled smoothly by the
    /// surface's height texture coordinate.
    private static func gradientTexture() -> TextureResource? {
        let width = 256
        var bytes = [UInt8](repeating: 0, count: width * 4)
        for x in 0..<width {
            let c = rampColor(Float(x) / Float(width - 1))
            bytes[x * 4 + 0] = UInt8(max(0, min(255, c.r * 255)))
            bytes[x * 4 + 1] = UInt8(max(0, min(255, c.g * 255)))
            bytes[x * 4 + 2] = UInt8(max(0, min(255, c.b * 255)))
            bytes[x * 4 + 3] = 255
        }
        guard let context = CGContext(
            data: &bytes, width: width, height: 1, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { return nil }
        return try? TextureResource.generate(
            from: image, options: .init(semantic: .color))
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
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var uvs: [SIMD2<Float>]
        var indices: [UInt32]
        var rim: [SIMD3<Float>]
    }

    private nonisolated static func computeSurface(_ job: SurfaceJob) -> SurfaceResult {
        let n = job.n
        let a = job.spacing
        let half = Float(n - 1) * a / 2
        let h = job.heights

        @inline(__always) func height(_ i: Int, _ j: Int) -> Float { h[j * n + i] }

        // One shared vertex per grid node — indexed triangles, so the
        // normals and the height texture coordinate interpolate
        // continuously across the whole sheet (no per-triangle seams).
        var positions = [SIMD3<Float>](); positions.reserveCapacity(n * n)
        var normals = [SIMD3<Float>](); normals.reserveCapacity(n * n)
        var uvs = [SIMD2<Float>](); uvs.reserveCapacity(n * n)
        for j in 0..<n {
            for i in 0..<n {
                let y = height(i, j)
                positions.append(job.center + SIMD3(Float(i) * a - half, y, Float(j) * a - half))
                let il = max(i - 1, 0), ir = min(i + 1, n - 1)
                let jl = max(j - 1, 0), jr = min(j + 1, n - 1)
                let dhdx = (height(ir, j) - height(il, j)) / (Float(ir - il) * a)
                let dhdz = (height(i, jr) - height(i, jl)) / (Float(jr - jl) * a)
                normals.append(simd_normalize(SIMD3(-dhdx, 1, -dhdz)))
                // u = height along the ramp; v anywhere on the 1-D texture.
                let u = min(max((y + heightSpan) / (2 * heightSpan), 0), 1)
                uvs.append(SIMD2(u, 0.5))
            }
        }

        var indices = [UInt32](); indices.reserveCapacity((n - 1) * (n - 1) * 6)
        for j in 0..<(n - 1) {
            for i in 0..<(n - 1) {
                let v00 = UInt32(j * n + i), v10 = UInt32(j * n + i + 1)
                let v01 = UInt32((j + 1) * n + i), v11 = UInt32((j + 1) * n + i + 1)
                indices += [v00, v10, v11, v00, v11, v01]
            }
        }

        // Rim loop for the boundary tube.
        @inline(__always) func position(_ i: Int, _ j: Int) -> SIMD3<Float> {
            positions[j * n + i]
        }
        var rim: [SIMD3<Float>] = []
        for i in 0..<n { rim.append(position(i, 0)) }
        for j in 1..<n { rim.append(position(n - 1, j)) }
        for i in stride(from: n - 2, through: 0, by: -1) { rim.append(position(i, n - 1)) }
        for j in stride(from: n - 2, through: 0, by: -1) { rim.append(position(0, j)) }

        return SurfaceResult(positions: positions, normals: normals,
                             uvs: uvs, indices: indices, rim: rim)
    }

    private func applySurface(_ result: SurfaceResult) {
        guard result.positions.count >= 3, result.indices.count >= 3 else {
            surfaceEntity.isEnabled = false
            return
        }
        surfaceEntity.isEnabled = true
        var descriptor = MeshDescriptor(name: "membrane")
        descriptor.positions = MeshBuffer(result.positions)
        descriptor.normals = MeshBuffer(result.normals)
        descriptor.textureCoordinates = MeshBuffer(result.uvs)
        descriptor.primitives = .triangles(result.indices)
        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            surfaceEntity.model?.mesh = mesh
        }
        if result.rim.count >= 2,
           let mesh = TubeMesh.tube(lines: [result.rim], radius: 0.004, sides: 4) {
            rimEntity.model = ModelComponent(mesh: mesh, materials: [rimMaterial])
        }
    }
}
