//
//  WavesRenderer.swift
//  Physics Playground — Waves module
//
//  Renders the 3D interference field, fully volumetric — no furniture:
//
//  · a 8×8×8 lattice of dots filling the region, each pulsing with the
//    live field at its point (scale = |u|), tinted once per configuration
//    by the standing envelope (bright where loud, dim where quiet);
//  · the SILENCE SURFACES — 3D sheets where the envelope cancels —
//    extracted by marching tetrahedra on the GeometryPipeline, exactly
//    like the electromagnetism module's equipotential shells;
//  · floating grabbable sources (teal in phase, orange inverted) and the
//    probe with its billboarded readout.
//
//  Frame-rate contract: the per-frame path is 512 scale writes plus a
//  few transforms; lattice tinting and isosurface extraction happen only
//  when the configuration changes (the latter off the main thread).
//

import Foundation
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
    static let latticeSide = 9

    var manipulatingSourceID: UUID?
    var isManipulatingProbe = false

    /// Parent for the probe's floating readout attachment.
    let probeAnchor = Entity()

    private let latticePool: EntityPool<ModelEntity>
    private var latticePoints: [SIMD3<Double>] = []
    private var latticePalette: [UnlitMaterial] = []
    private var latticeTintKeys: [Int]

    private let sourcePool: EntityPool<ModelEntity>
    private var sourceMaterialKeys: [String]
    private let probe: ModelEntity

    private let silenceEntity = ModelEntity()
    private let silenceMaterial: UnlitMaterial
    private var silencePipeline: GeometryPipeline<SilenceJob, SilenceResult>?

    private let renderLoop = RenderLoop()
    private var model: WavesModel?

    private struct FieldInputs: Equatable {
        var sources: [WaveSource]
        var frequency: Double
        var speed: Double
        var show: Bool
    }
    private var lastFieldInputs: FieldInputs?

    init() {
        // The lattice: shared mesh, per-dot material from a brightness
        // palette assigned when the configuration changes.
        let dotMesh = MeshResource.generateSphere(radius: 0.011)
        latticePalette = (0..<6).map { step in
            let t = CGFloat(step) / 5
            var material = UnlitMaterial(
                color: UIColor(red: 0.2 + 0.35 * t, green: 0.55 + 0.35 * t, blue: 0.65 + 0.3 * t, alpha: 1))
            material.blending = .transparent(opacity: .init(floatLiteral: Float(0.18 + 0.5 * t)))
            return material
        }
        let initialMaterial = latticePalette[2]
        let side = Self.latticeSide
        latticePool = EntityPool(budget: side * side * side) { container in
            let dot = ModelEntity(mesh: dotMesh, materials: [initialMaterial])
            container.addChild(dot)
            return dot
        }
        latticeTintKeys = Array(repeating: -1, count: latticePool.budget)

        let spacing = 2 * WavesModel.regionHalfExtent * 0.92 / Double(side - 1)
        let origin = WavesModel.regionCenter
            - SIMD3(repeating: WavesModel.regionHalfExtent * 0.92)
        var points: [SIMD3<Double>] = []
        for i in 0..<side {
            for j in 0..<side {
                for k in 0..<side {
                    points.append(origin + spacing * SIMD3(Double(i), Double(j), Double(k)))
                }
            }
        }
        latticePoints = points
        for (index, slot) in latticePool.slots.enumerated() {
            slot.entity.position = SIMD3<Float>(latticePoints[index])
            slot.entity.isEnabled = true
        }
        root.addChild(latticePool.root)

        // Silence surfaces.
        var silence = UnlitMaterial(color: DesignTokens.Palette.forceVectorUI)
        silence.blending = .transparent(opacity: 0.16)
        silence.faceCulling = .none
        silenceMaterial = silence
        root.addChild(silenceEntity)

        // Sources.
        let sourceMesh = MeshResource.generateSphere(radius: 0.032)
        sourcePool = EntityPool(budget: WavesModel.sourceBudget) { container in
            let sphere = ModelEntity(
                mesh: sourceMesh,
                materials: [UnlitMaterial(color: DesignTokens.Palette.waveSourceUI)]
            )
            Grabbable.configure(sphere, collisionRadius: 0.06)
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = "Wave source. Drag it anywhere in the field."
            sphere.components.set(accessibility)
            container.addChild(sphere)
            return sphere
        }
        sourceMaterialKeys = Array(repeating: "", count: sourcePool.budget)
        root.addChild(sourcePool.root)

        // Probe.
        probe = ModelEntity(
            mesh: .generateSphere(radius: 0.016),
            materials: [UnlitMaterial(color: .white)]
        )
        probe.name = Self.probeName
        Grabbable.configure(probe, collisionRadius: 0.05)
        var probeAccessibility = AccessibilityComponent()
        probeAccessibility.isAccessibilityElement = true
        probeAccessibility.label = "Probe. Park it anywhere to hear the field: amplitude and interference."
        probe.components.set(probeAccessibility)
        root.addChild(probe)

        probeAnchor.components.set(BillboardComponent())
        root.addChild(probeAnchor)

        silencePipeline = GeometryPipeline(
            compute: { Self.extractSilenceSurfaces($0) },
            apply: { [weak self] in self?.applySilenceSurfaces($0) }
        )
    }

    // MARK: Silence surface extraction (background, coalescing)

    private nonisolated struct SilenceJob: Sendable {
        var sources: [WaveSource]
        var frequency: Double
        var speed: Double
    }

    private nonisolated struct SilenceResult: Sendable {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
    }

    private nonisolated static func extractSilenceSurfaces(_ job: SilenceJob) -> SilenceResult {
        guard job.sources.count > 1 else { return SilenceResult() }
        // Threshold: a small fraction of a typical mid-field arrival, so
        // the surface hugs the true zero set without wrapping quiet
        // far-field corners.
        let meanAmplitude = job.sources.map(\.amplitude).reduce(0, +) / Double(job.sources.count)
        let level = 0.12 * meanAmplitude * (WaveField.falloffRadius / 0.3)

        func amplitude(_ p: SIMD3<Double>) -> Double {
            WaveField.steadyAmplitude(at: p, sources: job.sources,
                                      frequency: job.frequency, speed: job.speed)
        }

        let triangles = Isosurface.triangles(
            level: level,
            scalar: amplitude,
            outwardDirection: { point in
                // ∇A by central differences — "outward" is "away from silence".
                let h = 0.012
                return SIMD3(
                    amplitude(point + SIMD3(h, 0, 0)) - amplitude(point - SIMD3(h, 0, 0)),
                    amplitude(point + SIMD3(0, h, 0)) - amplitude(point - SIMD3(0, h, 0)),
                    amplitude(point + SIMD3(0, 0, h)) - amplitude(point - SIMD3(0, 0, h))
                )
            },
            center: WavesModel.regionCenter,
            extents: SIMD3(repeating: 2 * WavesModel.regionHalfExtent),
            resolution: 26
        )

        var result = SilenceResult()
        result.positions.reserveCapacity(triangles.count)
        for vertex in triangles {
            result.positions.append(SIMD3<Float>(vertex))
        }
        // Flat normals per triangle (adequate for a translucent sheet).
        var index = 0
        while index + 2 < result.positions.count {
            let a = result.positions[index]
            let b = result.positions[index + 1]
            let c = result.positions[index + 2]
            var normal = simd_cross(b - a, c - a)
            let length = simd_length(normal)
            normal = length > 1e-9 ? normal / length : SIMD3(0, 1, 0)
            result.normals.append(contentsOf: [normal, normal, normal])
            index += 3
        }
        return result
    }

    private func applySilenceSurfaces(_ result: SilenceResult) {
        guard !result.positions.isEmpty else {
            silenceEntity.model = nil
            return
        }
        var descriptor = MeshDescriptor(name: "silence")
        descriptor.positions = MeshBuffer(result.positions)
        descriptor.normals = MeshBuffer(result.normals)
        descriptor.primitives = .triangles(Array(0..<UInt32(result.positions.count)))
        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            silenceEntity.model = ModelComponent(mesh: mesh, materials: [silenceMaterial])
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

    private func render(_ model: WavesModel) {
        syncSources(model)
        syncConfiguration(model)
        pulseLattice(model)

        if !isManipulatingProbe {
            probe.position = SIMD3<Float>(model.probePosition)
        }
        probeAnchor.position = SIMD3<Float>(model.probePosition) + SIMD3(0, 0.09, 0)
    }

    private func syncSources(_ model: WavesModel) {
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
                slot.entity.position = SIMD3<Float>(source.wave.position)
                slot.payload.position = .zero
            }
        }
        for index in model.sources.count..<sourcePool.budget {
            sourcePool.slots[index].entity.isEnabled = false
        }
    }

    /// When the configuration changes: retint the lattice by the standing
    /// envelope and resubmit the silence-surface job.
    private func syncConfiguration(_ model: WavesModel) {
        let inputs = FieldInputs(
            sources: model.waveSources, frequency: model.frequency,
            speed: model.waveSpeed, show: model.showSilenceSurfaces
        )
        guard inputs != lastFieldInputs else { return }
        lastFieldInputs = inputs

        // Tint dots by how loud they'll ever get (the envelope).
        let reference = inputs.sources.map(\.amplitude).reduce(0, +)
            * WaveField.falloff(0.25)
        for (index, slot) in latticePool.slots.enumerated() {
            let envelope = WaveField.steadyAmplitude(
                at: latticePoints[index], sources: inputs.sources,
                frequency: inputs.frequency, speed: inputs.speed)
            let tint = min(Int(envelope / max(reference, 1e-12) * 5), 5)
            if latticeTintKeys[index] != tint {
                latticeTintKeys[index] = tint
                slot.payload.model?.materials = [latticePalette[tint]]
            }
        }

        if inputs.show {
            silencePipeline?.submit(SilenceJob(
                sources: inputs.sources, frequency: inputs.frequency, speed: inputs.speed))
        } else {
            silenceEntity.model = nil
        }
        silenceEntity.isEnabled = inputs.show
    }

    /// The per-frame heartbeat: every dot scales with the live |u(r, t)|.
    private func pulseLattice(_ model: WavesModel) {
        let sources = model.waveSources
        let frequency = model.frequency
        let speed = model.waveSpeed
        let time = model.time
        let reference = sources.map(\.amplitude).reduce(0, +) * WaveField.falloff(0.25)

        for (index, slot) in latticePool.slots.enumerated() {
            let u = WaveField.displacement(
                at: latticePoints[index], time: time,
                sources: sources, frequency: frequency, speed: speed)
            let normalized = min(abs(u) / max(reference, 1e-12), 1.6)
            slot.entity.scale = SIMD3(repeating: Float(0.25 + 0.75 * normalized))
        }
    }
}
