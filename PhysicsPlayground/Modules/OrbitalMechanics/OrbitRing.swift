//
//  OrbitRing.swift
//  The selected body's osculating conic as a grabbable ring; math in PhysicsCore.ApsisFrame.
//  The mesh is a canonical p = 1 conic at the orbit's exact eccentricity, rebuilt on the worker
//  when e moves past a threshold or the tube's canonical radius changes; per-frame cost is a
//  transform write, never an anisotropic squash (it fattens the tube's cross-section). The tube
//  is 1.4 mm in the ROOM whatever the orbit's size or the rig's zoom — the canonical radius is
//  divided by both — and the beads are counter-scaled against the rig by the same rule.
//  Bead collider equals visual radius; the ring carries no collider.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class OrbitRing {
    /// Add this to `systemRoot` — the frame the bodies and hand points live in.
    let root = Entity()

    private let conicCasing = ModelEntity()
    private let conicCore = ModelEntity()
    /// One VoiceOver adjust step on an apsis bead: which end, signed increments. Set by the SpaceView.
    var onAdjust: ((Apsis, Double) -> Void)?

    private let nearBead: ModelEntity
    private let farBead: ModelEntity

    /// Visual (and collision) radius of a bead, before rig compensation.
    static let beadRadius: Float = 0.014
    /// The core tube's radius in the room, metres.
    nonisolated static let roomCoreRadius: Float = 0.0014
    /// A change of eccentricity this large rebuilds the mesh; below it the
    /// drawn conic and the beads disagree by less than a tube width.
    nonisolated static let eccentricityThreshold = 0.002
    /// How many points a conic is sampled at.
    nonisolated static let sampleCount = 256

    /// What the current mesh was built for.
    private var applied: RingKey?
    private var pending: RingKey?
    private var pipeline: GeometryPipeline<RingJob, RingResult>?

    /// Abandons any ring rebuild in flight. See `OrbitalMechanicsRenderer.teardown`.
    func teardown() { pipeline?.cancel() }

    /// Last-frame reachability per bead, for the reach hysteresis.
    private var nearWasReachable = false
    private var farWasReachable = false

    init(accent: UIColor) {
        let (casingMaterial, coreMaterial) = Materials.contrastLine(
            accent, coreOpacity: 0.9, casingOpacity: 0.5)
        conicCasing.model = nil
        conicCore.model = nil
        // A speck until the first ring mesh replaces it, so not 8 000 triangles.
        conicCasing.components.set(ModelComponent(mesh: Primitives.sphere(radius: 0.0001, segments: 6),
                                                  materials: [casingMaterial]))
        conicCore.components.set(ModelComponent(mesh: Primitives.sphere(radius: 0.0001, segments: 6),
                                                materials: [coreMaterial]))
        // Casing first, core over it — darkness beneath light.
        root.addChild(conicCasing)
        root.addChild(conicCore)

        nearBead = Self.makeBead(name: Self.nearBeadName, accent: accent)
        farBead = Self.makeBead(name: Self.farBeadName, accent: accent)
        // VoiceOver verb is increment/decrement — the same reach `-apsisDrag` has from the CLI.
        for (bead, apsis) in [(nearBead, Apsis.near), (farBead, Apsis.far)] {
            SpatialActions.attach(
                to: bead,
                label: apsis == .near ? "Closest point of the orbit"
                                      : "Furthest point of the orbit",
                adjust: { [weak self] steps in self?.onAdjust?(apsis, steps) })
        }
        root.addChild(nearBead)
        root.addChild(farBead)
        root.isEnabled = false

        pipeline = GeometryPipeline(
            compute: { Self.computeRing($0) },
            apply: { [weak self] in self?.applyRing($0) })
    }

    static let nearBeadName = "apsis-near"
    static let farBeadName = "apsis-far"

    // MARK: Per frame

    /// Points the ring at one orbit (nil hides it). `occluders` are in the ring's own frame (relative to `primaryDisplay`); `head` nil = simulator, beads stay reachable for the CLI.
    func update(frame: ApsisFrame?,
                primaryDisplay: SIMD3<Float>,
                simToDisplay: Double,
                rigScale: Float,
                occluders: [(center: SIMD3<Float>, radius: Float)],
                head: SIMD3<Float>?) {
        guard let frame else {
            root.isEnabled = false
            nearWasReachable = false
            farWasReachable = false
            return
        }
        root.isEnabled = true
        root.position = primaryDisplay

        let scale = Float(simToDisplay)
        self.rigScale = rigScale
        orientConic(to: frame, scale: scale)

        // Beads sit at the two ends of the apse line, in display metres.
        let compensation = min(max(1 / max(rigScale, 0.001), 0.1), 3.0)
        place(bead: nearBead, at: frame.apsisPoint(.near), scale: scale,
              compensation: compensation, occluders: occluders, head: head,
              wasReachable: &nearWasReachable, exists: true)
        place(bead: farBead, at: frame.apsisPoint(.far), scale: scale,
              compensation: compensation, occluders: occluders, head: head,
              wasReachable: &farWasReachable, exists: frame.hasApoapsis)
    }

    private func orientConic(to frame: ApsisFrame, scale: Float) {
        let p = SIMD3<Float>(frame.periapsisDirection)
        let h = SIMD3<Float>(frame.orbitNormal)
        // The mesh is built with p̂ = +x, ĥ = +y. The third column must be the cross of the first two so the matrix is a rotation, not a reflection: p̂ × ĥ = −q̂.
        let basis = simd_float3x3(columns: (p, h, simd_cross(p, h)))
        let orientation = simd_quatf(basis)
        let size = Float(frame.semiLatusRectum) * scale
        for entity in [conicCasing, conicCore] {
            entity.orientation = orientation
            entity.scale = SIMD3(repeating: size)
        }
        requestMesh(RingKey(eccentricity: frame.eccentricity,
                            radii: Self.canonicalRadii(pDisplay: size, rigScale: rigScale)))
    }

    /// The rig scale the last `update` saw, for the tube's canonical radius.
    private var rigScale: Float = 1

    /// Core and casing radii in the canonical p = 1 frame that come out as
    /// `roomCoreRadius` (and its casing) in the room, whatever the orbit's
    /// semi-latus rectum or the rig's zoom. Both are bucketed — p by 3 %, the
    /// rig by 12 % — so an evolving orbit or a two-hand zoom does not ask for
    /// a new mesh every frame.
    nonisolated static func canonicalRadii(pDisplay: Float, rigScale: Float)
        -> (core: Float, casing: Float) {
        let p = pow(1.03, (log(max(pDisplay, 1e-4)) / log(1.03)).rounded())
        let rig = pow(1.12, (log(max(rigScale, 1e-3)) / log(1.12)).rounded())
        let core = roomCoreRadius / (p * rig)
        return (core, Materials.casingRadius(forCore: roomCoreRadius) / (p * rig))
    }

    private func place(bead: ModelEntity, at simPoint: SIMD3<Double>,
                       scale: Float, compensation: Float,
                       occluders: [(center: SIMD3<Float>, radius: Float)],
                       head: SIMD3<Float>?, wasReachable: inout Bool,
                       exists: Bool) {
        guard exists else {
            bead.isEnabled = false
            wasReachable = false
            return
        }
        let local = SIMD3<Float>(simPoint) * scale
        bead.position = local
        bead.scale = SIMD3(repeating: compensation)

        let worldRadius = Self.beadRadius * compensation
        let hidden = Self.isOccluded(bead: local, radius: worldRadius,
                                     by: occluders)
        let reachable = Self.isWithinReach(
            bead: local, head: head, wasReachable: wasReachable)
        wasReachable = reachable

        bead.isEnabled = !hidden && reachable
        // A hidden bead must also stop being a target — the collider rule.
        Self.setTargetable(bead, bead.isEnabled)
    }

    // MARK: The two suppression rules
    // Pure statics so the geometry is testable without a headset.

    /// Whether a bead is buried inside a body (a circular orbit parks the near bead on the planet).
    /// Both arguments are in the ring's own frame — an absolute-coordinate occluder list is offset by the primary's position.
    nonisolated static func isOccluded(
        bead: SIMD3<Float>, radius: Float,
        by occluders: [(center: SIMD3<Float>, radius: Float)]
    ) -> Bool {
        occluders.contains { simd_distance($0.center, bead) < $0.radius + radius }
    }

    /// Whether a bead is close enough to pinch, with hysteresis so one at arm's length cannot flicker.
    nonisolated static let reachOn: Float = 1.15
    nonisolated static let reachOff: Float = 1.35

    nonisolated static func isWithinReach(bead: SIMD3<Float>, head: SIMD3<Float>?,
                                          wasReachable: Bool) -> Bool {
        // nil head = simulator: stays reachable so the debug arguments can drive this path.
        guard let head else { return true }
        let distance = simd_distance(bead, head)
        return wasReachable ? distance <= reachOff : distance <= reachOn
    }

    // MARK: Hit testing

    /// Which apsis this entity is, if it is one of ours.
    func apsis(for entity: Entity) -> Apsis? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === nearBead { return .near }
            if candidate === farBead { return .far }
            if candidate === root { return nil }
            current = candidate.parent
        }
        return nil
    }

    /// Where a bead sits in display space, for seeding a `RelativeDrag`.
    func beadDisplayPoint(_ apsis: Apsis) -> SIMD3<Double> {
        let bead = apsis == .near ? nearBead : farBead
        return SIMD3<Double>(root.position + bead.position)
    }

    // MARK: The mesh

    /// What a mesh is built for: an exact eccentricity and the canonical radii.
    nonisolated struct RingKey: Sendable, Equatable {
        var eccentricity: Double
        var radii: (core: Float, casing: Float)

        static func == (lhs: RingKey, rhs: RingKey) -> Bool {
            lhs.eccentricity == rhs.eccentricity
                && lhs.radii.core == rhs.radii.core && lhs.radii.casing == rhs.radii.casing
        }
    }

    private nonisolated struct RingJob: Sendable {
        var key: RingKey
    }

    private nonisolated struct RingResult: Sendable {
        var key: RingKey
        var casing: TubeBuffers
        var core: TubeBuffers
    }

    /// Whether `next` needs a new mesh over `applied`: the eccentricity has
    /// moved past the threshold, the tube's radius bucket changed, or the
    /// conic changed kind (an ellipse and a hyperbola are different curves).
    nonisolated static func needsRebuild(applied: RingKey?, next: RingKey) -> Bool {
        guard let applied else { return true }
        if applied.radii.core != next.radii.core { return true }
        if (applied.eccentricity >= 1) != (next.eccentricity >= 1) { return true }
        return abs(applied.eccentricity - next.eccentricity) > eccentricityThreshold
    }

    private func requestMesh(_ key: RingKey) {
        guard Self.needsRebuild(applied: applied, next: key) else { return }
        // A job in flight for something close enough is left to land.
        if let pending, !Self.needsRebuild(applied: pending, next: key) { return }
        pending = key
        pipeline?.submit(RingJob(key: key))
    }

    /// Canonical conic at an exact eccentricity: p = 1, periapsis +x, normal
    /// +y; everything else is scale + rotation.
    nonisolated static func canonicalFrame(eccentricity e: Double) -> ApsisFrame {
        let clamped = max(e, 0)
        return ApsisFrame(
            periapsisDirection: SIMD3(1, 0, 0),
            orbitNormal: SIMD3(0, 1, 0),
            periapsisRadius: 1 / (1 + clamped),
            // Negative past parabolic: that is how the frame writes a hyperbola.
            apoapsisRadius: abs(1 - clamped) > 1e-12 ? 1 / (1 - clamped) : .infinity,
            trueAnomaly: 0, mu: 1)
    }

    private nonisolated static func computeRing(_ job: RingJob) -> RingResult {
        let points = canonicalFrame(eccentricity: job.key.eccentricity)
            .sampled(count: sampleCount)
            .map(SIMD3<Float>.init)
        return RingResult(
            key: job.key,
            casing: TubeMesh.buffers(lines: [points], radius: job.key.radii.casing),
            core: TubeMesh.buffers(lines: [points], radius: job.key.radii.core))
    }

    private func applyRing(_ result: RingResult) {
        guard let casing = TubeMesh.mesh(from: result.casing),
              let core = TubeMesh.mesh(from: result.core) else { return }
        if pending == result.key { pending = nil }
        conicCasing.model?.mesh = casing
        conicCore.model?.mesh = core
        applied = result.key
    }

    // MARK: Building

    private static func makeBead(name: String, accent: UIColor) -> ModelEntity {
        // Bright and solid: this is the handle, not the surface it sits on.
        let bead = ModelEntity(
            mesh: Primitives.sphere(radius: beadRadius, segments: 24),
            materials: [Materials.grip(emissive: accent, glow: 0.55)])
        bead.name = name
        // Collider equals the visual radius.
        bead.components.set(CollisionComponent(
            shapes: [Primitives.collisionSphere(radius: beadRadius)]))
        bead.components.set(HoverEffectComponent())
        SpatialActions.describe(bead, label: name == nearBeadName
                                    ? "Closest point of the orbit. Pull to reshape it."
                                    : "Furthest point of the orbit. Pull to reshape it.")
        bead.isEnabled = false
        return bead
    }

    private static func setTargetable(_ entity: Entity, _ targetable: Bool) {
        let has = entity.components[InputTargetComponent.self] != nil
        if targetable, !has {
            entity.components.set(InputTargetComponent())
        } else if !targetable, has {
            entity.components.remove(InputTargetComponent.self)
        }
    }
}
