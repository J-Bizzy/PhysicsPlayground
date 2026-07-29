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
//    extracted by marching tetrahedra on the GeometryPipeline;
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
    private let silenceCasingEntity = ModelEntity()
    private let silenceMaterial: UnlitMaterial
    private let silenceCasingMaterial: UnlitMaterial
    private var silencePipeline: GeometryPipeline<SilenceJob, SilenceResult>?

    // The wavelength ruler: a physical lambda between the first two
    // sources — alternating half-wave segments (the spatial period,
    // drawn AS geometry) with the value floating at the midpoint.
    private static let rulerBudget = 48
    private let rulerRoot = Entity()
    private var rulerSegments: [ModelEntity] = []
    private var rulerLabelPivot: Entity!
    private var rulerLabel: ModelEntity!
    private var rulerMeshCache: [Int: MeshResource] = [:]
    private let rulerLabelMaterial = UnlitMaterial(color: UIColor(white: 1, alpha: 0.9))

    private struct FieldInputs: Equatable {
        var sources: [WaveSource]
        var frequency: Double
        var speed: Double
        var show: Bool
    }
    private var lastFieldInputs: FieldInputs?

    // Expanding wavefront shells: each source sheds a translucent sphere
    // every wave period, growing at the wave speed — the crests made
    // visible. A moving source's shells bunch ahead and stretch behind,
    // so this is where the Doppler effect actually shows.
    private static let shellBudget = 40
    private static let shellMaxRadius = Float(WavesModel.regionHalfExtent * 1.4)
    private static let shellFadeBuckets = 6
    private let wavefrontsRoot = Entity()
    private var shellPool: EntityPool<ModelEntity>!
    private var wavefrontMaterials: [[UnlitMaterial]] = []   // [tint][fade bucket]
    private var shellBirths = [Double](repeating: 0, count: shellBudget)
    private var shellCenters = [SIMD3<Float>](repeating: .zero, count: shellBudget)
    private var shellActive = [Bool](repeating: false, count: shellBudget)
    private var shellTints = [Int](repeating: 0, count: shellBudget)
    private var shellMatKeys = [Int](repeating: -1, count: shellBudget)
    private var nextShell = 0
    /// The last crest time emitted, per source index.
    private var lastEmit: [Double] = []

    init() {
        root.addChild(Lighting.keyLight())
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

        // Wavefront crests: a small pool of thin rings, each a unit
        // circle that always faces the viewer (so it reads as a clean
        // expanding outline, never a solid ball that fogs the room), and
        // is recycled round-robin as sources shed new crests.
        let shellMaterials = [
            Self.shellMaterials(DesignTokens.Palette.waveSourceUI),
            Self.shellMaterials(DesignTokens.Palette.waveInvertedUI),
        ]
        wavefrontMaterials = shellMaterials
        let unitCircle: [SIMD3<Float>] = (0...56).map { i in
            let t = Float(i) / 56 * 2 * .pi
            return SIMD3(cos(t), sin(t), 0)
        }
        let ringMesh = TubeMesh.tube(lines: [unitCircle], radius: 0.008)
            ?? MeshResource.generateSphere(radius: 0.02)
        shellPool = EntityPool(budget: Self.shellBudget) { container in
            let ring = ModelEntity(mesh: ringMesh, materials: [shellMaterials[0][0]])
            container.addChild(ring)
            // Face the user, so a sphere of crests always reads as a
            // circle outline centred on where the source emitted it.
            container.components.set(BillboardComponent())
            container.isEnabled = false
            return ring
        }
        wavefrontsRoot.addChild(shellPool.root)
        root.addChild(wavefrontsRoot)

        // Silence contours: a bright ring over a dark casing. Nearly
        // opaque — an outline can afford to be solid where a sheet
        // could not.
// Sheets, not hairlines: low-opacity glass so the surfaces
        // behind stay visible through the one in front. That layering
        // IS the nesting — the thing the old rings could only imply.
        var sheet = UnlitMaterial(color: UIColor(
            red: 0.55, green: 0.86, blue: 1.0, alpha: 1))
        // Low enough that four nested sheets still add up to
        // something you can see the room through.
        sheet.blending = .transparent(opacity: 0.085)
        silenceMaterial = sheet
        silenceCasingMaterial = sheet
        root.addChild(silenceCasingEntity)
        root.addChild(silenceEntity)

        // Wavelength ruler segments: alternation is by index, so each
        // segment's material is assigned exactly once, here.
        var crest = UnlitMaterial(color: DesignTokens.Palette.waveSourceUI)
        crest.blending = .transparent(opacity: 0.72)
        var trough = UnlitMaterial(color: .white)
        trough.blending = .transparent(opacity: 0.2)
        let segmentMesh = MeshResource.generateCylinder(height: 1, radius: 0.0024)
        for index in 0..<Self.rulerBudget {
            let segment = ModelEntity(
                mesh: segmentMesh,
                materials: [index % 2 == 0 ? crest : trough])
            segment.isEnabled = false
            rulerRoot.addChild(segment)
            rulerSegments.append(segment)
        }
        rulerLabelPivot = Entity()
        rulerLabelPivot.components.set(BillboardComponent())
        rulerLabel = ModelEntity()
        rulerLabelPivot.addChild(rulerLabel)
        rulerRoot.addChild(rulerLabelPivot)
        root.addChild(rulerRoot)

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
            materials: [Materials.energized(.white, roughness: 0.25, glow: 0.18)]
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
        /// Flat triangle list of the nodal SURFACES themselves.
        var triangles: [SIMD3<Float>] = []
        var isEmpty = true
    }

    /// Resolution of the marching-tetrahedra lattice the nodal
    /// surfaces are pulled out of. 28³ is ~22,000 field evaluations per
    /// submit — the same order as the seven slices it replaces, spent
    /// on a surface instead of on rings.
    private nonisolated static let silenceResolution = 28

    /// THE SILENCE, AS SURFACES.
    ///
    /// For two sources the quiet set is a family of hyperboloid SHEETS
    /// nested about the line joining them — and the user is standing
    /// among them. The old version cut those sheets into rings, seven
    /// slices perpendicular to the source axis, because rings are cheap
    /// and read as nested. But a ring is a cross-section: it tells you
    /// a surface is there without ever being one. You cannot walk
    /// through it, lean past it, or watch it curve away over your
    /// shoulder.
    ///
    /// Marching tetrahedra on the steady-state amplitude gives the
    /// sheets themselves. Held at low opacity so you can see the ones
    /// behind, and drawn double-sided so a sheet you have walked
    /// through is still there when you turn around.
    private nonisolated static func extractSilenceSurfaces(_ job: SilenceJob) -> SilenceResult {
        guard job.sources.count > 1 else { return SilenceResult() }
        // A small fraction of a typical mid-field arrival, so the
        // surface hugs the true zero set without chasing quiet
        // far-field corners.
        let meanAmplitude = job.sources.map(\.amplitude).reduce(0, +) / Double(job.sources.count)
        let level = 0.12 * meanAmplitude * (WaveField.falloffRadius / 0.3)

        var low = job.sources[0].position, high = job.sources[0].position
        for source in job.sources.dropFirst() {
            low = simd_min(low, source.position)
            high = simd_max(high, source.position)
        }
        let midpoint = (low + high) / 2
        let separation = simd_length(high - low)
        // Bounded to the region that actually reads as nesting;
        // the sheets flare without limit and engulf the room.
        let reach = min(max(separation * 1.35, 0.40),
                        WavesModel.regionHalfExtent * 0.8)

        let amplitude: @Sendable (SIMD3<Double>) -> Double = { point in
            WaveField.steadyAmplitude(at: point, sources: job.sources,
                                      frequency: job.frequency, speed: job.speed)
        }
        let points = Isosurface.triangles(
            level: level,
            scalar: amplitude,
            // The quiet side is INSIDE the sheet, so the outward
            // direction is up the amplitude gradient.
            outwardDirection: { point in
                let h = 0.01
                return SIMD3(
                    amplitude(point + SIMD3(h, 0, 0)) - amplitude(point - SIMD3(h, 0, 0)),
                    amplitude(point + SIMD3(0, h, 0)) - amplitude(point - SIMD3(0, h, 0)),
                    amplitude(point + SIMD3(0, 0, h)) - amplitude(point - SIMD3(0, 0, h)))
            },
            center: midpoint,
            extents: SIMD3(repeating: 2 * reach),
            resolution: Self.silenceResolution)

        var result = SilenceResult()
        result.triangles = points.map { SIMD3<Float>($0) }
        result.isEmpty = points.count < 3
        return result
    }

    private func applySilenceSurfaces(_ result: SilenceResult) {
        guard !result.isEmpty else {
            silenceEntity.model = nil
            silenceCasingEntity.model = nil
            return
        }
        // Both windings, so a sheet you have walked through is still
        // there when you turn round to look at it.
        var positions = result.triangles
        var indices: [UInt32] = []
        indices.reserveCapacity(positions.count * 2)
        for base in stride(from: 0, to: positions.count, by: 3) {
            let i = UInt32(base)
            indices.append(contentsOf: [i, i + 1, i + 2])
            indices.append(contentsOf: [i, i + 2, i + 1])
        }
        var descriptor = MeshDescriptor(name: "silence")
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else {
            silenceEntity.model = nil
            return
        }
        silenceEntity.model = ModelComponent(mesh: mesh, materials: [silenceMaterial])
        silenceCasingEntity.model = nil
        positions.removeAll()
    }

    // MARK: Per-frame tick (from SceneEvents.Update)

    func tick(_ model: WavesModel, listener: SIMD3<Double>? = nil) {
        syncSources(model)
        syncConfiguration(model)
        pulseLattice(model)
        updateWavefronts(model)
        updateListening(model, at: listener)

        if !isManipulatingProbe {
            probe.position = SIMD3<Float>(model.probePosition)
        }
        probeAnchor.position = SIMD3<Float>(model.probePosition) + SIMD3(0, 0.09, 0)
    }

    // MARK: Hearing the field at your own head

    /// The module's real payoff, and nothing invited it before: the
    /// interference pattern is a pattern in the ROOM, so you should be
    /// able to walk into a node and hear it go quiet.
    ///
    /// A tone plays at the source frequency and its loudness tracks the
    /// steady-state amplitude at the listener's actual head position,
    /// evaluated with exactly the same WaveField the visuals use. Step
    /// sideways across a nodal sheet and the sound drops away; step back
    /// and it returns. Reading a number off a probe card is not the same
    /// experience as losing the sound in your own ears.
    private var listenerVoice: ToneVoice?
    private let listenerEmitter = Entity()

    private func updateListening(_ model: WavesModel, at listener: SIMD3<Double>?) {
        guard model.listenToField, let listener else {
            listenerVoice?.mute()
            return
        }
        if listenerVoice == nil {
            root.addChild(listenerEmitter)
            listenerVoice = ToneVoice(on: listenerEmitter, range: (-70)...(-14))
        }
        // Play from the head, so it is heard as "the room is quiet here",
        // not "that speaker over there is quiet".
        listenerEmitter.position = SIMD3<Float>(listener)
        guard listenerVoice?.start() == true else { return }

        let amplitude = WaveField.steadyAmplitude(
            at: listener, sources: model.waveSources,
            frequency: model.frequency, speed: model.waveSpeed)
        // Full scale = every source arriving in phase at the reference
        // distance, so a true antinode reads as loud and a node as silent.
        let full = model.sources.reduce(0.0) { $0 + $1.wave.amplitude }
        // Audible pitch from the (deliberately slowed) wave frequency:
        // the field runs at ~1.5 Hz so the crests are walkable, which is
        // far below hearing. Two decades up puts it in the ear while
        // keeping every ratio — double the frequency, double the note.
        let pitch = model.frequency * 150
        listenerVoice?.update(
            pitchHz: pitch,
            loudness: Sonification.loudness(amplitude, full: max(full, 1e-9), knee: 0.85))
    }

    // MARK: Wavefront shells (the Doppler visualization)

    /// One material per fade bucket: bright when the crest is fresh and
    /// small, fading toward nothing as it spreads — the real 1/r decay,
    /// and it keeps the big outer rings from crowding the room.
    private static func shellMaterials(_ color: UIColor) -> [UnlitMaterial] {
        (0..<shellFadeBuckets).map { bucket in
            let f = Float(bucket) / Float(shellFadeBuckets - 1)   // 0 fresh … 1 far
            var material = UnlitMaterial(color: color)
            material.blending = .transparent(
                opacity: .init(floatLiteral: 0.55 * (1 - f) + 0.05))
            return material
        }
    }

    /// Sheds and grows the wavefront spheres. Each source emits one crest
    /// per wave period at its live position; every shell then expands at
    /// the wave speed. Because a shell is anchored to where the source
    /// WAS when it emitted, a moving source's shells crowd together ahead
    /// of it and spread behind — the Doppler picture, straight from the
    /// same motion that drives the field's retarded-distance shift.
    private func updateWavefronts(_ model: WavesModel) {
        guard model.showWavefronts else {
            if wavefrontsRoot.isEnabled {
                wavefrontsRoot.isEnabled = false
                for i in shellActive.indices where shellActive[i] {
                    shellActive[i] = false
                    shellPool.slots[i].entity.isEnabled = false
                }
                lastEmit.removeAll()
            }
            return
        }
        wavefrontsRoot.isEnabled = true

        // One emission clock per current source; (re)seed to now so a
        // freshly shown layer doesn't dump a burst of old crests.
        if lastEmit.count != model.sources.count {
            lastEmit = Array(repeating: model.time, count: model.sources.count)
        }
        let period = 1.0 / max(model.frequency, 0.01)   // sim seconds between crests
        for (index, source) in model.sources.enumerated() {
            var emitted = 0
            while model.time - lastEmit[index] >= period, emitted < 4 {
                lastEmit[index] += period
                emitShell(at: SIMD3<Float>(source.wave.position),
                          birth: lastEmit[index],
                          tint: source.wave.phaseInverted ? 1 : 0)
                emitted += 1
            }
        }

        // Grow the live shells; retire any that have swept past the room.
        for i in shellActive.indices where shellActive[i] {
            let radius = Float(model.waveSpeed * (model.time - shellBirths[i]))
            if radius <= 0 || radius > Self.shellMaxRadius {
                shellActive[i] = false
                shellPool.slots[i].entity.isEnabled = false
                continue
            }
            let slot = shellPool.slots[i]
            slot.entity.position = shellCenters[i]
            slot.entity.scale = SIMD3(repeating: radius)
            // Fade with size; only touch the material when the bucket flips.
            let bucket = min(Int(radius / Self.shellMaxRadius * Float(Self.shellFadeBuckets)),
                             Self.shellFadeBuckets - 1)
            let key = shellTints[i] * Self.shellFadeBuckets + bucket
            if shellMatKeys[i] != key {
                shellMatKeys[i] = key
                slot.payload.model?.materials = [wavefrontMaterials[shellTints[i]][bucket]]
            }
        }
    }

    private func emitShell(at center: SIMD3<Float>, birth: Double, tint: Int) {
        let i = nextShell
        nextShell = (nextShell + 1) % Self.shellBudget
        shellActive[i] = true
        shellBirths[i] = birth
        shellCenters[i] = center
        shellTints[i] = tint
        shellMatKeys[i] = -1   // force a material assign on the first grow
        let slot = shellPool.slots[i]
        slot.entity.position = center
        slot.entity.scale = SIMD3(repeating: 0.001)
        slot.entity.isEnabled = true
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
            silenceCasingEntity.model = nil
        }
        silenceEntity.isEnabled = inputs.show
        silenceCasingEntity.isEnabled = inputs.show

        syncWavelengthRuler(model)
    }

    /// Lays the ruler along the line between the first two sources:
    /// each segment spans exactly lambda/2, so interference geometry
    /// (path differences in half-waves) can be READ off the room.
    private func syncWavelengthRuler(_ model: WavesModel) {
        guard model.sources.count >= 2 else {
            rulerRoot.isEnabled = false
            return
        }
        let a = model.sources[0].wave.position
        let b = model.sources[1].wave.position
        let distance = simd_distance(a, b)
        guard distance > 0.08 else {
            rulerRoot.isEnabled = false
            return
        }
        rulerRoot.isEnabled = true
        let direction = (b - a) / distance
        let half = model.wavelength / 2
        let orientation = VectorFieldArrows.rotationFromYAxis(to: SIMD3<Float>(direction))
        for (index, segment) in rulerSegments.enumerated() {
            let start = Double(index) * half
            guard start < distance else {
                segment.isEnabled = false
                continue
            }
            let end = min(start + half, distance)
            segment.isEnabled = true
            segment.position = SIMD3<Float>(a + direction * (start + end) / 2)
            segment.scale = SIMD3(1, Float(end - start), 1)
            segment.orientation = orientation
        }

        rulerLabelPivot.position = SIMD3<Float>((a + b) / 2) + SIMD3(0, 0.05, 0)
        let centimeters = Int((model.wavelength * 100).rounded())
        let mesh: MeshResource
        if let cached = rulerMeshCache[centimeters] {
            mesh = cached
        } else {
            mesh = MeshResource.generateText(
                "λ = \(centimeters) cm", extrusionDepth: 0.002,
                font: .systemFont(ofSize: 0.022, weight: .semibold))
            rulerMeshCache[centimeters] = mesh
        }
        rulerLabel.model = ModelComponent(mesh: mesh, materials: [rulerLabelMaterial])
        let bounds = mesh.bounds
        rulerLabel.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
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
