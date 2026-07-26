//
//  WaveMediumRenderer.swift
//  Physics Playground — Elastic Field (Springs module)
//
//  Renders the resonance drumhead: a VERTICAL shaded membrane facing
//  the user, so the mode shapes and nodal lines read straight on. The
//  height field is triangulated every frame with real per-vertex
//  normals (room light rakes the ripples) and shaded by a smooth
//  topographic heatmap sampled per-pixel from a gradient texture.
//
//  Three things make the resonance legible:
//   · marker grains scattered on the face migrate away from the shaking
//     antinodes and pile up on the still nodal lines — live Chladni
//     figures;
//   · a driver puck rides the shaken center, visibly pumping in and out;
//   · the whole sheet blooms brighter as it rings, and a spatial tone
//     sings louder and higher with the drive.
//
//  The heavy vertex math runs on a GeometryPipeline worker; the main
//  thread uploads the mesh and animates the light grain layer.
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

    /// Displacement (m) the colour ramp spans, ±this. Tighter than the
    /// pull clamp so the higher modes — which ring at smaller amplitude —
    /// still sweep well into the warm and cool ends of the ramp.
    private static let heightSpan: Float = 0.09

    /// The tilted frame the whole drumhead lives in.
    private let plateRoot = Entity()
    private let surfaceEntity = ModelEntity()
    private let contourEntity = ModelEntity()
    private let contourMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: UIColor(white: 0.06, alpha: 1))
        material.blending = .transparent(opacity: 0.55)
        return material
    }()
    private let rimEntity = ModelEntity()
    private let grainsEntity = ModelEntity()
    private let driverEntity = ModelEntity()
    private let heldHalo = ModelEntity()
    private let audioEmitter = Entity()

    private var surfaceMaterial = PhysicallyBasedMaterial()
    private var lastBloomBucket = -1

    private let rimMaterial: UnlitMaterial = {
        var m = UnlitMaterial(color: UIColor(red: 0.3, green: 0.85, blue: 0.85, alpha: 1))
        m.blending = .transparent(opacity: 0.85)
        return m
    }()
    private let grainMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.96, blue: 0.86, alpha: 1))

    private var surfacePipeline: GeometryPipeline<SurfaceJob, SurfaceResult>?
    private var toneController: AudioPlaybackController?

    // MARK: Chladni grains

    private struct Grain { var x: Float; var y: Float }
    private static let grainCount = 340
    private var grains: [Grain] = []
    /// A slow envelope of how much each node shakes — high at antinodes,
    /// near zero on the nodal lines. Grains flee the high spots.
    private var vibEnvelope: [Float]

    init() {
        let half = Float(WaveMediumModel.halfSide)
        vibEnvelope = [Float](repeating: 0, count: WaveMediumModel.gridCount * WaveMediumModel.gridCount)
        grains = (0..<Self.grainCount).map { _ in
            Grain(x: Float.random(in: -half...half), y: Float.random(in: -half...half))
        }

        root.addChild(Lighting.keyLight())

        // The lit surface, heatmap-shaded by height.
        if let texture = Self.gradientTexture() {
            surfaceMaterial.baseColor = .init(tint: .white, texture: .init(texture))
            surfaceMaterial.emissiveColor = .init(color: .white, texture: .init(texture))
            surfaceMaterial.emissiveIntensity = 0.35
        } else {
            surfaceMaterial.baseColor = .init(tint: UIColor(red: 0.15, green: 0.78, blue: 0.68, alpha: 1))
        }
        surfaceMaterial.roughness = 0.28
        surfaceMaterial.metallic = 0.0
        surfaceMaterial.faceCulling = .none
        surfaceEntity.model = ModelComponent(
            mesh: .generateSphere(radius: 0.0001), materials: [surfaceMaterial])
        // The whole plate hangs off one tilted root: the mesh builder
        // keeps working in the sheet's own flat frame, and the lean is a
        // single orientation. Nothing in the wave equation, the grain
        // walk or the mode shapes knows the plate is tilted.
        plateRoot.position = SIMD3<Float>(WaveMediumModel.center)
        plateRoot.orientation = simd_quatf(
            angle: -Float(WaveMediumModel.tilt), axis: [1, 0, 0])
        root.addChild(plateRoot)
        plateRoot.addChild(surfaceEntity)
        plateRoot.addChild(contourEntity)
        plateRoot.addChild(rimEntity)

        // The grain layer (Chladni sand) — one rebuilt mesh of tiny
        // camera-facing quads.
        grainsEntity.model = ModelComponent(
            mesh: .generateSphere(radius: 0.0001), materials: [grainMaterial])
        plateRoot.addChild(grainsEntity)

        // The driver puck at the shaken center.
        var driverMat = PhysicallyBasedMaterial()
        driverMat.baseColor = .init(tint: UIColor(red: 0.3, green: 0.85, blue: 0.85, alpha: 1))
        driverMat.roughness = 0.2
        driverMat.metallic = 0.7
        driverMat.emissiveColor = .init(color: UIColor(red: 0.3, green: 0.9, blue: 0.9, alpha: 1))
        driverMat.emissiveIntensity = 0.5
        driverEntity.model = ModelComponent(
            mesh: .generateCylinder(height: 0.02, radius: 0.028), materials: [driverMat])
        // The cylinder's axis is Y; lay it along Z so its face points at
        // the user and it pumps in and out.
        driverEntity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(driverEntity)

        // The grab volume: an invisible slab over the vertical face,
        // thin front-to-back (displacement) so it sits well clear of the
        // orb controls below and in front of it.
        let collider = ModelEntity()
        collider.name = Self.surfaceName
        collider.components.set(InputTargetComponent())
        collider.components.set(CollisionComponent(shapes: [
            .generateBox(width: half * 2 + 0.06,
                         height: half * 2 + 0.06,
                         depth: Float(WaveMediumModel.pluckClamp) * 2 + 0.1)
        ]))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Resonance drumhead. Reach in and pull it, or let the shaker ring its modes."
        collider.components.set(accessibility)
        plateRoot.addChild(collider)

        // The held-point halo.
        var haloMaterial = UnlitMaterial(color: .white)
        haloMaterial.blending = .transparent(opacity: 0.5)
        heldHalo.model = ModelComponent(
            mesh: .generateSphere(radius: 0.03), materials: [haloMaterial])
        heldHalo.isEnabled = false
        root.addChild(heldHalo)

        audioEmitter.position = SIMD3<Float>(WaveMediumModel.center)
        root.addChild(audioEmitter)

        surfacePipeline = GeometryPipeline(
            compute: { Self.computeSurface($0) },
            apply: { [weak self] in self?.applySurface($0) }
        )
    }

    /// A perceptual blue→teal→red ramp for a signed displacement field.
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

        // Advance the grain random-walk (cheap), then hand the heavy
        // geometry — membrane triangulation AND grain quads — to the
        // worker in one job.
        let sheet = model.sheet
        let grainCenters = advanceGrains(sheet: sheet)
        surfacePipeline?.submit(SurfaceJob(
            heights: sheet.height.map { Float($0) },
            n: sheet.n, spacing: Float(WaveMediumModel.spacing),
            center: .zero,
            grainCenters: grainCenters))

        updateDriver(model: model)
        updateBloom(model: model)
        updateAudio(model: model)

        if let node = model.heldNode {
            heldHalo.isEnabled = true
            heldHalo.position = SIMD3<Float>(model.world(i: node.i, j: node.j))
        } else {
            heldHalo.isEnabled = false
        }
    }

    // MARK: Chladni grains

    /// Advances the grain random-walk one frame and returns each grain's
    /// world center. Cheap (a few hundred iterations); the quad geometry
    /// is built from these on the worker.
    private func advanceGrains(sheet: ElasticSheet) -> [SIMD3<Float>] {
        let n = WaveMediumModel.gridCount
        let a = Float(WaveMediumModel.spacing)
        let half = Float(WaveMediumModel.halfSide)
        let margin = a
        let heights = sheet.height

        @inline(__always) func node(_ x: Float, _ y: Float) -> (Int, Int) {
            let i = min(max(Int(((x + half) / a).rounded()), 0), n - 1)
            let j = min(max(Int(((y + half) / a).rounded()), 0), n - 1)
            return (i, j)
        }

        for k in 0..<vibEnvelope.count {
            vibEnvelope[k] += 0.06 * (Float(abs(heights[k])) - vibEnvelope[k])
        }

        var centers = [SIMD3<Float>](); centers.reserveCapacity(grains.count)
        for idx in 0..<grains.count {
            var g = grains[idx]
            let (i, j) = node(g.x, g.y)
            let env = vibEnvelope[j * n + i]
            // Where the sheet shakes, grains hop randomly and drift off;
            // on the still nodal lines they settle and stack up.
            if env > 0.006 {
                let angle = Float.random(in: 0..<(2 * .pi))
                let step = min(env * 6.5, a * 0.9)
                g.x = min(max(g.x + cos(angle) * step, -half + margin), half - margin)
                g.y = min(max(g.y + sin(angle) * step, -half + margin), half - margin)
            }
            grains[idx] = g
            let (gi, gj) = node(g.x, g.y)
            let z = Float(heights[gj * n + gi])
            centers.append(SIMD3(g.x, g.y, z + 0.006))
        }
        return centers
    }

    // MARK: Driver puck & bloom

    private func updateDriver(model: WaveMediumModel) {
        driverEntity.isEnabled = model.driveOn
        guard model.driveOn else { return }
        let c = WaveMediumModel.driveCoord
        driverEntity.position = SIMD3<Float>(model.world(i: c.i, j: c.j))
            + SIMD3<Float>(WaveMediumModel.faceNormal) * 0.012
    }

    /// Brighten the whole sheet as it rings, change-gated so we only
    /// re-assign the material when the glow visibly steps.
    private func updateBloom(model: WaveMediumModel) {
        let live = model.resonanceLive
        let bucket = Int(live * 6)
        guard bucket != lastBloomBucket else { return }
        lastBloomBucket = bucket
        surfaceMaterial.emissiveIntensity = 0.32 + Float(live) * 0.7
        surfaceEntity.model?.materials = [surfaceMaterial]
    }

    // MARK: Audio

    private var lastToneGain: Double = .nan
    private var lastToneSpeed: Double = .nan

    private func updateAudio(model: WaveMediumModel) {
        if toneController == nil {
            toneController = SoundPalette.startResonanceTone(on: audioEmitter)
        }
        guard let controller = toneController else { return }
        // Sweep the audible pitch with the (subsonic) drive frequency —
        // writes gated to real changes so the controller isn't poked
        // sixty times a second while nothing moves.
        let range = WaveMediumModel.driveFrequencyRange
        let t = (model.driveFrequency - range.lowerBound) / (range.upperBound - range.lowerBound)
        let pitch = 150.0 + min(max(t, 0), 1) * (820.0 - 150.0)
        let speed = pitch / SoundPalette.resonanceToneBaseHz
        if abs(speed - lastToneSpeed) > 0.002 {
            lastToneSpeed = speed
            controller.speed = speed
        }
        // Louder the harder it rings; silent when the shaker is off.
        let gain = model.driveOn ? (-68 + model.resonanceLive * 58) : -80
        if abs(gain - lastToneGain) > 0.4 {
            lastToneGain = gain
            controller.gain = gain
        }
    }

    // MARK: Surface build (worker)

    private nonisolated struct SurfaceJob: Sendable {
        var heights: [Float]
        var n: Int
        var spacing: Float
        var center: SIMD3<Float>
        var grainCenters: [SIMD3<Float>]
    }

    private nonisolated struct SurfaceResult: Sendable {
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var uvs: [SIMD2<Float>]
        var indices: [UInt32]
        var rim: [SIMD3<Float>]
        var grainPositions: [SIMD3<Float>]
        var grainIndices: [UInt32]
        /// Iso-height contours drawn ON the surface.
        var contours = TubeBuffers()
    }

    /// The height levels contour lines are drawn at, as a fraction of
    /// the colormap's span. Symmetric about the rest plane so crest and
    /// trough read alike.
    private nonisolated static let contourLevels: [Float] =
        [-0.72, -0.48, -0.24, 0.24, 0.48, 0.72]

    private nonisolated static func computeSurface(_ job: SurfaceJob) -> SurfaceResult {
        let n = job.n
        let a = job.spacing
        let half = Float(n - 1) * a / 2
        let h = job.heights

        @inline(__always) func height(_ i: Int, _ j: Int) -> Float { h[j * n + i] }

        // One shared vertex per node — indexed triangles, so normals and
        // the height texture coordinate interpolate continuously. The
        // sheet is VERTICAL: (i, j) span the room's x and y, and the
        // displacement rides +z toward the user.
        var positions = [SIMD3<Float>](); positions.reserveCapacity(n * n)
        var normals = [SIMD3<Float>](); normals.reserveCapacity(n * n)
        var uvs = [SIMD2<Float>](); uvs.reserveCapacity(n * n)
        for j in 0..<n {
            for i in 0..<n {
                let z = height(i, j)
                positions.append(job.center + SIMD3(Float(i) * a - half, Float(j) * a - half, z))
                let il = max(i - 1, 0), ir = min(i + 1, n - 1)
                let jl = max(j - 1, 0), jr = min(j + 1, n - 1)
                let dzdx = (height(ir, j) - height(il, j)) / (Float(ir - il) * a)
                let dzdy = (height(i, jr) - height(i, jl)) / (Float(jr - jl) * a)
                normals.append(simd_normalize(SIMD3(-dzdx, -dzdy, 1)))
                let u = min(max((z + heightSpan) / (2 * heightSpan), 0), 1)
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

        @inline(__always) func position(_ i: Int, _ j: Int) -> SIMD3<Float> {
            positions[j * n + i]
        }
        var rim: [SIMD3<Float>] = []
        for i in 0..<n { rim.append(position(i, 0)) }
        for j in 1..<n { rim.append(position(n - 1, j)) }
        for i in stride(from: n - 2, through: 0, by: -1) { rim.append(position(i, n - 1)) }
        for j in stride(from: n - 2, through: 0, by: -1) { rim.append(position(0, j)) }

        // Grain quads — small camera-facing squares at each grain center.
        let s: Float = 0.0038
        var grainPositions = [SIMD3<Float>]()
        grainPositions.reserveCapacity(job.grainCenters.count * 4)
        var grainIndices = [UInt32]()
        grainIndices.reserveCapacity(job.grainCenters.count * 6)
        for (m, c) in job.grainCenters.enumerated() {
            let b = UInt32(m * 4)
            grainPositions.append(c + SIMD3(-s, -s, 0))
            grainPositions.append(c + SIMD3(s, -s, 0))
            grainPositions.append(c + SIMD3(s, s, 0))
            grainPositions.append(c + SIMD3(-s, s, 0))
            grainIndices += [b, b + 1, b + 2, b, b + 2, b + 3]
        }

        // Iso-height CONTOURS, drawn on the surface itself.
        //
        // A shaded height field only reads as relief when the light
        // happens to rake it; under flat room ambient a rippling
        // membrane can look like a smooth colour wash — which is exactly
        // how the drumhead was reading. Contour lines make the shape
        // explicit and quantitative: closed rings around each antinode,
        // crowding where the surface is steep, vanishing on the nodal
        // lines. It is the same trick a map uses for a mountain, and it
        // survives any lighting.
        var contourLines: [[SIMD3<Float>]] = []
        for level in contourLevels {
            let value = level * heightSpan
            let segments = MarchingSquares.contour(
                level: Double(value),
                scalar: { local in
                    // Bilinear sample of the height lattice.
                    let fx = (Float(local.x) + half) / a
                    let fy = (Float(local.y) + half) / a
                    let i0 = min(max(Int(fx), 0), n - 1), j0 = min(max(Int(fy), 0), n - 1)
                    let i1 = min(i0 + 1, n - 1), j1 = min(j0 + 1, n - 1)
                    let tx = fx - Float(i0), ty = fy - Float(j0)
                    let h00 = height(i0, j0), h10 = height(i1, j0)
                    let h01 = height(i0, j1), h11 = height(i1, j1)
                    let top = h00 + (h10 - h00) * tx
                    let bottom = h01 + (h11 - h01) * tx
                    return Double(top + (bottom - top) * ty)
                },
                center: .zero,
                extents: SIMD2(Double(half * 2), Double(half * 2)),
                resolution: 54)
            for polyline in MarchingSquares.chain(segments, tolerance: 1e-7)
            where polyline.count > 3 {
                // Lift each contour a hair off the surface so it never
                // z-fights the shaded mesh it is describing.
                contourLines.append(polyline.map {
                    SIMD3<Float>(Float($0.x), Float($0.y), value + 0.0022)
                })
            }
        }

        return SurfaceResult(positions: positions, normals: normals,
                             uvs: uvs, indices: indices, rim: rim,
                             grainPositions: grainPositions,
                             grainIndices: grainIndices,
                             contours: TubeMesh.buffers(lines: contourLines, radius: 0.0013))
    }

    private func applySurface(_ result: SurfaceResult) {
        if let contourMesh = TubeMesh.mesh(from: result.contours) {
            contourEntity.model = ModelComponent(mesh: contourMesh,
                                                 materials: [contourMaterial])
            contourEntity.isEnabled = true
        } else {
            contourEntity.isEnabled = false
        }
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
        if !result.grainPositions.isEmpty {
            var grainDescriptor = MeshDescriptor(name: "grains")
            grainDescriptor.positions = MeshBuffer(result.grainPositions)
            grainDescriptor.normals = MeshBuffer(
                [SIMD3<Float>](repeating: [0, 0, 1], count: result.grainPositions.count))
            grainDescriptor.primitives = .triangles(result.grainIndices)
            if let mesh = try? MeshResource.generate(from: [grainDescriptor]) {
                grainsEntity.model?.mesh = mesh
            }
        }
    }
}
