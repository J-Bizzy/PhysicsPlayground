//
//  WavesRenderer.swift
//  Physics Playground — Waves module
//
//  Renders the ripple tank: a 64×64 deformable water surface, source
//  pucks (teal in phase, orange inverted), and the probe. This is the
//  module where "correct physics" and "90 fps" genuinely collide — a
//  finely-meshed surface re-generated per frame would blow the budget —
//  so the surface is a RealityKit LowLevelMesh: the vertex buffer is
//  written in place every frame (positions + normals; ~4k vertices,
//  ~16k sin() calls) and the GPU sees the same mesh object, no
//  allocation and no MeshResource rebuild anywhere in the hot path.
//
//  Surface heights are exaggerated ×6 for visibility (real ripples are
//  millimeters); the legend and panels disclose it, and every number
//  shown is the true value.
//

import Foundation
import Metal
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class WavesRenderer {
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    static let probeName = "probe"
    static let poolCenter = SIMD3<Float>(0, 0.92, -1.1)
    /// Ripples are millimeters tall; the surface shows them ×6.
    static let verticalExaggeration: Float = 6

    var manipulatingSourceID: UUID?
    var isManipulatingProbe = false

    /// Parent for the probe's floating readout attachment.
    let probeAnchor = Entity()

    private static let gridN = 64
    private static let extent = Float(WavesModel.poolHalfExtent)

    private let poolRoot = Entity()
    private let surfaceEntity = ModelEntity()
    private var surfaceMesh: LowLevelMesh?
    private var heights: [Float]

    private let sourcePool: EntityPool<ModelEntity>
    private var sourceMaterialKeys: [String]
    private let probe: ModelEntity

    private let renderLoop = RenderLoop()
    private var model: WavesModel?

    private struct SurfaceVertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    init() {
        heights = Array(repeating: 0, count: Self.gridN * Self.gridN)
        sourceMaterialKeys = Array(repeating: "", count: WavesModel.sourceBudget)

        poolRoot.position = Self.poolCenter
        root.addChild(poolRoot)

        // Pool frame: four quiet dark rails.
        let railMaterial = SimpleMaterial(
            color: UIColor(white: 0.16, alpha: 1), roughness: 0.7, isMetallic: false)
        let railLong = MeshResource.generateBox(size: [2 * Self.extent + 0.06, 0.03, 0.03])
        let railShort = MeshResource.generateBox(size: [0.03, 0.03, 2 * Self.extent + 0.06])
        for (mesh, offset) in [
            (railLong, SIMD3<Float>(0, 0, Self.extent + 0.015)),
            (railLong, SIMD3<Float>(0, 0, -Self.extent - 0.015)),
            (railShort, SIMD3<Float>(Self.extent + 0.015, 0, 0)),
            (railShort, SIMD3<Float>(-Self.extent - 0.015, 0, 0)),
        ] {
            let rail = ModelEntity(mesh: mesh, materials: [railMaterial])
            rail.position = offset
            poolRoot.addChild(rail)
        }

        // The deformable water surface.
        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(tint: UIColor(red: 0.25, green: 0.55, blue: 0.75, alpha: 1))
        water.roughness = 0.22
        water.metallic = 0.0
        water.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        surfaceEntity.model = ModelComponent(
            mesh: .generateBox(size: [0.01, 0.01, 0.01]),  // replaced on build
            materials: [water]
        )
        poolRoot.addChild(surfaceEntity)

        // Source pucks (grabbable).
        let puckMesh = MeshResource.generateCylinder(height: 0.02, radius: 0.032)
        sourcePool = EntityPool(budget: WavesModel.sourceBudget) { container in
            let puck = ModelEntity(
                mesh: puckMesh,
                materials: [UnlitMaterial(color: DesignTokens.Palette.waveSourceUI)]
            )
            Grabbable.configure(puck, collisionRadius: 0.06)
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = "Wave source. Drag it across the pool."
            puck.components.set(accessibility)
            container.addChild(puck)
            return puck
        }
        poolRoot.addChild(sourcePool.root)

        // Probe.
        probe = ModelEntity(
            mesh: .generateSphere(radius: 0.014),
            materials: [UnlitMaterial(color: .white)]
        )
        probe.name = Self.probeName
        Grabbable.configure(probe, collisionRadius: 0.045)
        var probeAccessibility = AccessibilityComponent()
        probeAccessibility.isAccessibilityElement = true
        probeAccessibility.label = "Probe. Park it anywhere to read the local wave amplitude."
        probe.components.set(probeAccessibility)
        poolRoot.addChild(probe)

        probeAnchor.components.set(BillboardComponent())
        poolRoot.addChild(probeAnchor)

        buildSurfaceMesh()
    }

    // MARK: LowLevelMesh surface

    private func buildSurfaceMesh() {
        let n = Self.gridN
        let vertexCount = n * n
        let indexCount = (n - 1) * (n - 1) * 6

        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = vertexCount
        descriptor.indexCapacity = indexCount
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
            .init(semantic: .normal, format: .float3, layoutIndex: 0,
                  offset: MemoryLayout<SIMD3<Float>>.stride),
        ]
        descriptor.vertexLayouts = [
            .init(bufferIndex: 0, bufferOffset: 0,
                  bufferStride: MemoryLayout<SurfaceVertex>.stride),
        ]

        guard let mesh = try? LowLevelMesh(descriptor: descriptor) else { return }

        mesh.withUnsafeMutableIndices { raw in
            guard let indices = raw.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
            var cursor = 0
            for row in 0..<(n - 1) {
                for column in 0..<(n - 1) {
                    let a = UInt32(row * n + column)
                    let b = a + 1
                    let c = a + UInt32(n)
                    let d = c + 1
                    indices[cursor] = a; indices[cursor + 1] = c; indices[cursor + 2] = b
                    indices[cursor + 3] = b; indices[cursor + 4] = c; indices[cursor + 5] = d
                    cursor += 6
                }
            }
        }

        let bounds = BoundingBox(
            min: [-Self.extent, -0.12, -Self.extent],
            max: [Self.extent, 0.12, Self.extent]
        )
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexOffset: 0, indexCount: indexCount,
                topology: .triangle, materialIndex: 0, bounds: bounds),
        ])

        guard let resource = try? MeshResource(from: mesh) else { return }
        surfaceEntity.model?.mesh = resource
        surfaceMesh = mesh
    }

    private func updateSurface(_ model: WavesModel) {
        guard let mesh = surfaceMesh else { return }
        let n = Self.gridN
        let spacing = 2 * Self.extent / Float(n - 1)
        let sources = model.waveSources
        let frequency = model.frequency
        let speed = model.waveSpeed
        let envelope = model.showEnvelope
        let time = model.time

        // Height pass (true physics, then exaggerated for display).
        for row in 0..<n {
            let z = Double(-Self.extent + Float(row) * spacing)
            for column in 0..<n {
                let x = Double(-Self.extent + Float(column) * spacing)
                let point = SIMD2(x, z)
                let height = envelope
                    ? WaveField.steadyAmplitude(at: point, sources: sources,
                                                frequency: frequency, speed: speed)
                    : WaveField.displacement(at: point, time: time, sources: sources,
                                             frequency: frequency, speed: speed)
                heights[row * n + column] = Float(height) * Self.verticalExaggeration
            }
        }

        // Vertex pass: positions + central-difference normals.
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            guard let vertices = raw.baseAddress?.assumingMemoryBound(to: SurfaceVertex.self)
            else { return }
            for row in 0..<n {
                for column in 0..<n {
                    let index = row * n + column
                    let left = heights[row * n + max(column - 1, 0)]
                    let right = heights[row * n + min(column + 1, n - 1)]
                    let near = heights[max(row - 1, 0) * n + column]
                    let far = heights[min(row + 1, n - 1) * n + column]
                    let normal = simd_normalize(SIMD3<Float>(
                        (left - right) / (2 * spacing), 1, (near - far) / (2 * spacing)))
                    vertices[index] = SurfaceVertex(
                        position: SIMD3(
                            -Self.extent + Float(column) * spacing,
                            heights[index],
                            -Self.extent + Float(row) * spacing),
                        normal: normal
                    )
                }
            }
        }
    }

    // MARK: Render loop

    func startObserving(_ model: WavesModel) {
        self.model = model
        renderLoop.start { [weak self, weak model] in
            guard let self, let model else { return }
            self.render(model)
        }
    }

    /// World point → pool-plane coordinates (meters from pool center).
    func planePoint(fromWorld world: SIMD3<Float>) -> SIMD2<Double> {
        let local = world - Self.poolCenter
        return SIMD2(Double(local.x), Double(local.z))
    }

    private func render(_ model: WavesModel) {
        for (index, slot) in sourcePool.slots.enumerated() {
            guard index < model.sources.count else {
                slot.entity.isEnabled = false
                continue
            }
            let source = model.sources[index]
            slot.entity.isEnabled = true
            if slot.payload.name != source.id.uuidString {
                slot.payload.name = source.id.uuidString
            }

            // Color = phase; brightness = selection.
            let key = (source.wave.phaseInverted ? "inverted" : "inPhase")
                + (source.id == model.selectedID ? "-selected" : "")
            if sourceMaterialKeys[index] != key {
                sourceMaterialKeys[index] = key
                let base = source.wave.phaseInverted
                    ? DesignTokens.Palette.waveInvertedUI
                    : DesignTokens.Palette.waveSourceUI
                var material = UnlitMaterial(color: base)
                if source.id != model.selectedID {
                    material.blending = .transparent(opacity: 0.75)
                }
                slot.payload.model?.materials = [material]
            }

            if source.id == manipulatingSourceID {
                // Hand owns it.
            } else {
                slot.entity.position = SIMD3(
                    Float(source.wave.position.x), 0.014, Float(source.wave.position.y))
                slot.payload.position = .zero
            }
        }
        for index in model.sources.count..<sourcePool.budget {
            sourcePool.slots[index].entity.isEnabled = false
        }

        if !isManipulatingProbe {
            probe.position = SIMD3(
                Float(model.probePosition.x), 0.035, Float(model.probePosition.y))
        }
        probeAnchor.position = SIMD3(
            Float(model.probePosition.x), 0.16, Float(model.probePosition.y))

        // The hot path: rewrite the surface for the current time/state.
        updateSurface(model)
    }
}
