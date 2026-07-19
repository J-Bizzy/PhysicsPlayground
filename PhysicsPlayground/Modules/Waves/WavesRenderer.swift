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
//  Frame-rate contract: all spatial field math (distances, falloff,
//  trig) folds into two cached phasor coefficients per dot — computed
//  off the main thread when the configuration changes — so the per-frame
//  path is one fused multiply-add per dot (u = c·cosωt − s·sinωt, exact;
//  see WaveFieldTests) plus scale writes gated on visible change.
//  Isosurface extraction also runs off-main. Ticked per frame from
//  SceneEvents.Update (observation loops starve during grabs — house
//  rule since the EM module's device findings).
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
    private var latticePalette: [UnlitMaterial] = []
    private var latticeTintKeys: [Int]

    // The phasor cache: u(dot, t) = c·cos(ωt) − s·sin(ωt), refreshed off
    // the main thread whenever the configuration changes.
    private var latticeC: [Float]
    private var latticeS: [Float]
    private var latticeScaleKeys: [Float]
    private var latticeReference: Float = 1
    private var latticePipeline: GeometryPipeline<LatticeJob, LatticeResult>?

    private let sourcePool: EntityPool<ModelEntity>
    private var sourceMaterialKeys: [String]
    private let probe: ModelEntity

    private let silenceEntity = ModelEntity()
    private let silenceMaterial: UnlitMaterial
    private var silencePipeline: GeometryPipeline<SilenceJob, SilenceResult>?

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
        latticeC = Array(repeating: 0, count: latticePool.budget)
        latticeS = Array(repeating: 0, count: latticePool.budget)
        latticeScaleKeys = Array(repeating: 0, count: latticePool.budget)

        for (index, slot) in latticePool.slots.enumerated() {
            slot.entity.position = SIMD3<Float>(Self.latticePoints[index])
            slot.entity.isEnabled = true
        }
        root.addChild(latticePool.root)

        // Silence surfaces.
        var silence = UnlitMaterial(color: DesignTokens.Palette.forceVectorUI)
        silence.blending = .transparent(opacity: 0.16)
        silence.faceCulling = .none
        silenceMaterial = silence
        root.addChild(silenceEntity)

        // Sources: a Blender-authored speaker puck inside a phase-tinted
        // translucent shell (the shell's color is the in-phase/inverted
        // indicator; the speaker is the body).
        let speakerPrototype = try? Entity.load(named: "WaveSpeaker")
        let sourceMesh = MeshResource.generateSphere(radius: 0.04)
        sourcePool = EntityPool(budget: WavesModel.sourceBudget) { container in
            let sphere = ModelEntity(
                mesh: sourceMesh,
                materials: [UnlitMaterial(color: DesignTokens.Palette.waveSourceUI)]
            )
            if let speakerPrototype {
                sphere.addChild(speakerPrototype.clone(recursive: true))
            }
            Grabbable.configureTouchTarget(sphere, collisionRadius: 0.06)
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
        Grabbable.configureTouchTarget(probe, collisionRadius: 0.05)
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
        latticePipeline = GeometryPipeline(
            compute: { Self.computeLattice($0) },
            apply: { [weak self] in self?.applyLattice($0) }
        )
    }

    /// The dot positions — fixed for the module's lifetime, shared with
    /// the background phasor computation.
    private nonisolated static let latticePoints: [SIMD3<Double>] = {
        let side = latticeSide
        let spacing = 2 * WavesModel.regionHalfExtent * 0.92 / Double(side - 1)
        let origin = WavesModel.regionCenter
            - SIMD3(repeating: WavesModel.regionHalfExtent * 0.92)
        var points: [SIMD3<Double>] = []
        points.reserveCapacity(side * side * side)
        for i in 0..<side {
            for j in 0..<side {
                for k in 0..<side {
                    points.append(origin + spacing * SIMD3(Double(i), Double(j), Double(k)))
                }
            }
        }
        return points
    }()

    // MARK: Lattice phasor cache (background, coalescing)

    private nonisolated struct LatticeJob: Sendable {
        var sources: [WaveSource]
        var frequency: Double
        var speed: Double
    }

    private nonisolated struct LatticeResult: Sendable {
        var c: [Float]
        var s: [Float]
        var tints: [Int]
        var reference: Float
    }

    private nonisolated static func computeLattice(_ job: LatticeJob) -> LatticeResult {
        let count = latticePoints.count
        var c = [Float](repeating: 0, count: count)
        var s = [Float](repeating: 0, count: count)
        var tints = [Int](repeating: 0, count: count)
        // The brightness yardstick: all sources arriving in phase at a
        // typical mid-field distance.
        let reference = job.sources.map(\.amplitude).reduce(0, +)
            * WaveField.falloff(0.25)
        for index in 0..<count {
            let phasor = WaveField.phasorCoefficients(
                at: latticePoints[index], sources: job.sources,
                frequency: job.frequency, speed: job.speed)
            c[index] = Float(phasor.c)
            s[index] = Float(phasor.s)
            // √(c² + s²) IS the standing envelope (tested) — the tint
            // comes free with the cache.
            let envelope = (phasor.c * phasor.c + phasor.s * phasor.s).squareRoot()
            tints[index] = min(Int(envelope / max(reference, 1e-12) * 5), 5)
        }
        return LatticeResult(c: c, s: s, tints: tints, reference: Float(reference))
    }

    private func applyLattice(_ result: LatticeResult) {
        guard result.c.count == latticePool.budget else { return }
        latticeC = result.c
        latticeS = result.s
        latticeReference = result.reference
        for (index, slot) in latticePool.slots.enumerated()
        where latticeTintKeys[index] != result.tints[index] {
            latticeTintKeys[index] = result.tints[index]
            slot.payload.model?.materials = [latticePalette[result.tints[index]]]
        }
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

    // MARK: Per-frame tick (from SceneEvents.Update)

    func tick(_ model: WavesModel) {
        syncSources(model)
        syncConfiguration(model)
        pulseLattice(model)

        if !isManipulatingProbe {
            probe.position = SIMD3<Float>(model.probePosition)
        }
        probeAnchor.position = SIMD3<Float>(model.probePosition) + SIMD3(0, 0.09, 0)
    }

    /// The +/− sign language from the EM module: a billboarded glyph
    /// above each source — + in phase, − inverted (the vertical stroke
    /// hides). Color already says it; now it reads outright.
    private var sourceSignVerticals: [Int: ModelEntity] = [:]

    private func ensureSourceSign(_ index: Int, on container: Entity) {
        guard sourceSignVerticals[index] == nil else { return }
        let pivot = Entity()
        pivot.components.set(BillboardComponent())
        pivot.position = [0, 0.085, 0]
        let strokeMaterial = UnlitMaterial(color: UIColor(white: 1, alpha: 0.9))
        let horizontal = ModelEntity(
            mesh: .generateBox(size: [0.018, 0.0045, 0.0025], cornerRadius: 0.001),
            materials: [strokeMaterial])
        let vertical = ModelEntity(
            mesh: .generateBox(size: [0.0045, 0.018, 0.0025], cornerRadius: 0.001),
            materials: [strokeMaterial])
        pivot.addChild(horizontal)
        pivot.addChild(vertical)
        container.addChild(pivot)
        sourceSignVerticals[index] = vertical
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
            ensureSourceSign(index, on: slot.entity)
            sourceSignVerticals[index]?.isEnabled = !source.wave.phaseInverted
            let key = (source.wave.phaseInverted ? "inverted" : "inPhase")
                + (source.id == model.selectedID ? "-selected" : "")
            if sourceMaterialKeys[index] != key {
                sourceMaterialKeys[index] = key
                let base = source.wave.phaseInverted
                    ? DesignTokens.Palette.waveInvertedUI
                    : DesignTokens.Palette.waveSourceUI
                var material = UnlitMaterial(color: base)
                // Translucent either way so the speaker model reads
                // through its phase-tinted shell.
                material.blending = .transparent(
                    opacity: source.id == model.selectedID ? 0.45 : 0.25)
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

    /// When the configuration changes: refresh the phasor cache (which
    /// carries the tints) and resubmit the silence-surface job — both off
    /// the main thread.
    private func syncConfiguration(_ model: WavesModel) {
        let inputs = FieldInputs(
            sources: model.waveSources, frequency: model.frequency,
            speed: model.waveSpeed, show: model.showSilenceSurfaces
        )
        guard inputs != lastFieldInputs else { return }
        lastFieldInputs = inputs

        latticePipeline?.submit(LatticeJob(
            sources: inputs.sources, frequency: inputs.frequency, speed: inputs.speed))

        if inputs.show {
            silencePipeline?.submit(SilenceJob(
                sources: inputs.sources, frequency: inputs.frequency, speed: inputs.speed))
        } else {
            silenceEntity.model = nil
        }
        silenceEntity.isEnabled = inputs.show
    }

    /// The per-frame heartbeat: every dot scales with the live |u(r, t)|,
    /// folded to u = c·cos(ωt) − s·sin(ωt) — two trig calls per FRAME
    /// (not per dot per source), then a multiply-add per dot. Scale
    /// writes are skipped below visible change (~1.5% of dot size).
    private func pulseLattice(_ model: WavesModel) {
        let omega = 2 * .pi * model.frequency
        let cosT = Float(cos(omega * model.time))
        let sinT = Float(sin(omega * model.time))
        let reference = max(latticeReference, 1e-12)

        for index in latticePool.slots.indices {
            let u = latticeC[index] * cosT - latticeS[index] * sinT
            let normalized = min(abs(u) / reference, 1.6)
            let scale = 0.25 + 0.75 * normalized
            guard abs(scale - latticeScaleKeys[index]) > 0.015 else { continue }
            latticeScaleKeys[index] = scale
            latticePool.slots[index].entity.scale = SIMD3(repeating: scale)
        }
    }
}
