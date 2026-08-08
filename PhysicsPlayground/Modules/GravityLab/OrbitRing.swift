//
//  OrbitRing.swift
//  Physics Playground — Gravity Lab module
//
//  THE ORBIT, AS A THING IN THE ROOM.
//
//  A selected body's osculating conic, drawn as a ring around its
//  primary, with one grabbable bead at each end of the apse line. Pull a
//  bead and the ellipse reshapes under your hand: outward and it
//  stretches, sideways and the whole orbit swings about the Sun, upward
//  and the orbital plane tilts. The math is `PhysicsCore.ApsisFrame`;
//  this file is only the geometry and the two rules about when a bead is
//  allowed to be a target.
//
//  ZERO PER-FRAME MESH WORK, and the trick is worth stating because it
//  is the whole reason this can be redrawn every frame. A conic is
//
//      r(ν) = p / (1 + e·cos ν)
//
//  and `p` enters as a plain multiplier — so every orbit of a given
//  ECCENTRICITY is the same curve at a different UNIFORM SCALE. One mesh
//  per eccentricity bucket, cached, and the per-frame cost is a transform
//  write. Thirty-four buckets at a step of 0.03 covers e ∈ [0, 1), which
//  is the same "a continuous quantity does not need a continuous asset"
//  argument the material canon makes about banked opacity ramps.
//
//  Note what is NOT done: the ring is not a circle squashed on one axis.
//  An anisotropic scale would squash the tube's cross-section with it —
//  2.3× fatter on one axis at e = 0.9 — and the ring would visibly change
//  thickness as it went round. Scaling a p = 1 conic keeps the tube
//  circular for free.
//
//  THE BEADS ARE CONTROLS, AND CONTROLS OBEY THE COLLIDER RULE. Their
//  collision radius equals their visual radius — no generosity, because
//  "an input-targetable collider must be no larger than the thing it
//  represents" is absolute (DECISIONS.md, the invisible scale plate). And
//  they are counter-scaled against the two-hand rig, which matters more
//  than it sounds: this module's rig runs to 9×, so an uncompensated
//  14 mm bead would be a 12.6 cm sphere at full zoom — a region collider,
//  the banned pattern, at full size. THE RING ITSELF CARRIES NO COLLIDER
//  AT ALL: a collision shape wrapped around a metre-wide circle is that
//  same ban with a different name.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class OrbitRing {
    /// Add this to `systemRoot` — the same frame the bodies live in, and
    /// the same frame a hand arrives in via `displayPoint(fromWorld:)`.
    let root = Entity()

    private let conicCasing = ModelEntity()
    private let conicCore = ModelEntity()
    private let nearBead: ModelEntity
    private let farBead: ModelEntity

    /// Visual (and collision) radius of a bead, before rig compensation.
    static let beadRadius: Float = 0.014
    /// Eccentricity bucket width for the mesh cache.
    static let eccentricityStep = 0.03
    /// How many points a cached conic is sampled at.
    static let sampleCount = 256
    private static let coreRadius: Float = 0.0018

    private var meshCache: [Int: (casing: MeshResource, core: MeshResource)] = [:]
    private var appliedBucket: Int?
    private var pendingBucket: Int?
    private var pipeline: GeometryPipeline<RingJob, RingResult>?

    /// Abandons any ring rebuild in flight. See
    /// `GravityLabRenderer.teardown`.
    func teardown() { pipeline?.cancel() }

    /// Whether each bead was a target last frame, for the reach
    /// hysteresis. Without it a bead sitting exactly at arm's length
    /// blinks in and out with the user's breathing.
    private var nearWasReachable = false
    private var farWasReachable = false

    init(accent: UIColor) {
        let (casingMaterial, coreMaterial) = Materials.contrastLine(
            accent, coreOpacity: 0.9, casingOpacity: 0.5)
        conicCasing.model = nil
        conicCore.model = nil
        conicCasing.components.set(ModelComponent(mesh: .generateSphere(radius: 0.0001),
                                                  materials: [casingMaterial]))
        conicCore.components.set(ModelComponent(mesh: .generateSphere(radius: 0.0001),
                                                materials: [coreMaterial]))
        // Casing first, core over it — darkness beneath light.
        root.addChild(conicCasing)
        root.addChild(conicCore)

        nearBead = Self.makeBead(name: Self.nearBeadName, accent: accent)
        farBead = Self.makeBead(name: Self.farBeadName, accent: accent)
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

    /// Points the ring at one orbit, or hides it.
    ///
    /// - Parameters:
    ///   - frame: the conic to draw, or nil for "no honest ring here".
    ///   - primaryDisplay: the focus, in display metres.
    ///   - simToDisplay: display metres per simulation metre.
    ///   - rigScale: the two-hand rig's current scale, for bead
    ///     compensation.
    ///   - occluders: every body's display centre and radius IN THE
    ///     RING'S OWN FRAME — that is, relative to `primaryDisplay`, so a bead
    ///     buried inside a planet stops being a target.
    ///   - head: the viewer in `root`'s own frame, or nil in the
    ///     simulator (where every bead stays reachable so the CLI can
    ///     still drive them).
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
        // The cached mesh is built with p̂ = +x, ĥ = +y (so q̂ = ĥ × p̂ is
        // −z). A rotation's columns are where it sends the basis vectors,
        // and the third must be the cross of the first two for the matrix
        // to be a rotation rather than a reflection: p̂ × ĥ = −q̂.
        let basis = simd_float3x3(columns: (p, h, simd_cross(p, h)))
        let orientation = simd_quatf(basis)
        let size = Float(frame.semiLatusRectum) * scale
        for entity in [conicCasing, conicCore] {
            entity.orientation = orientation
            entity.scale = SIMD3(repeating: size)
        }
        requestMesh(forEccentricity: frame.eccentricity)
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
        // A hidden bead is not merely invisible, it stops being a target:
        // an unhittable collider floating in front of a planet is exactly
        // the contention the collider rule exists to prevent.
        Self.setTargetable(bead, bead.isEnabled)
    }

    // MARK: The two suppression rules
    //
    // Pure statics, because both are geometry and both deserve a test
    // that does not need a headset to run.

    /// Whether a bead is buried inside a body.
    ///
    /// This is not cosmetic. A circular orbit has no periapsis of its
    /// own, so `ApsisFrame` points the apse line at the BODY — which puts
    /// the near bead exactly on the planet. Hiding it costs nothing,
    /// because when r_p = r_a the two beads do the same thing and the far
    /// one is a complete substitute.
    /// BOTH ARGUMENTS ARE IN THE RING'S OWN FRAME. `place` positions a
    /// bead relative to `root`, which sits on the primary — so an
    /// occluder list in ABSOLUTE display coordinates is offset from the
    /// beads by exactly the primary's position, and every test is wrong
    /// by that much.
    ///
    /// It was, until 2026-08-07, and `reset()` hid it: with the Sun at
    /// the origin the two frames coincide and the arithmetic is
    /// accidentally right. Press "Twin suns" — which puts the primaries
    /// at ±0.2 AU — and beads sitting inside a planet stayed targetable
    /// while beads in open space were hidden and stripped of their
    /// input target, intermittently, as the pair orbited.
    nonisolated static func isOccluded(
        bead: SIMD3<Float>, radius: Float,
        by occluders: [(center: SIMD3<Float>, radius: Float)]
    ) -> Bool {
        occluders.contains { simd_distance($0.center, bead) < $0.radius + radius }
    }

    /// Whether a bead is close enough to a head to be pinched, with
    /// hysteresis so one sitting at arm's length cannot flicker.
    ///
    /// A bead exists only where a hand could actually reach it. The outer
    /// solar system is genuinely out of arm's reach at any scale the room
    /// allows, and the honest answer there is a ring you can read and not
    /// touch — not a proxy handle, and certainly not a tether that fakes
    /// the distance away.
    nonisolated static let reachOn: Float = 1.15
    nonisolated static let reachOff: Float = 1.35

    nonisolated static func isWithinReach(bead: SIMD3<Float>, head: SIMD3<Float>?,
                                          wasReachable: Bool) -> Bool {
        // No head pose means the simulator, where nothing can be pinched
        // anyway and the debug arguments still have to drive this path.
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

    // MARK: The mesh cache

    private nonisolated struct RingJob: Sendable {
        var bucket: Int
    }

    private nonisolated struct RingResult: Sendable {
        var bucket: Int
        var casing: TubeBuffers?
        var core: TubeBuffers?
    }

    private func requestMesh(forEccentricity e: Double) {
        let bucket = Self.bucket(forEccentricity: e)
        if let cached = meshCache[bucket] {
            if appliedBucket != bucket {
                conicCasing.model?.mesh = cached.casing
                conicCore.model?.mesh = cached.core
                appliedBucket = bucket
            }
            return
        }
        guard pendingBucket != bucket else { return }
        pendingBucket = bucket
        pipeline?.submit(RingJob(bucket: bucket))
    }

    nonisolated static func bucket(forEccentricity e: Double) -> Int {
        // Everything at or past parabolic shares one open-curve bucket:
        // a hyperbola's drawn arc is dominated by where it is clipped,
        // not by its eccentricity, so the extra buckets would be meshes
        // nobody could tell apart.
        e >= 1 ? -1 : Int(max(e, 0) / eccentricityStep)
    }

    /// The canonical conic for a bucket: semi-latus rectum 1, periapsis
    /// on +x, normal on +y. Everything else is a uniform scale and a
    /// rotation.
    nonisolated static func canonicalFrame(forBucket bucket: Int) -> ApsisFrame {
        let e = bucket < 0 ? 1.6 : (Double(bucket) + 0.5) * eccentricityStep
        return ApsisFrame(
            periapsisDirection: SIMD3(1, 0, 0),
            orbitNormal: SIMD3(0, 1, 0),
            periapsisRadius: 1 / (1 + e),
            apoapsisRadius: abs(1 - e) > 1e-12 ? 1 / (1 - e) : .infinity,
            trueAnomaly: 0, mu: 1)
    }

    private nonisolated static func computeRing(_ job: RingJob) -> RingResult {
        let points = canonicalFrame(forBucket: job.bucket)
            .sampled(count: sampleCount)
            .map(SIMD3<Float>.init)
        return RingResult(
            bucket: job.bucket,
            casing: TubeMesh.buffers(
                lines: [points],
                radius: Materials.casingRadius(forCore: coreRadius)),
            core: TubeMesh.buffers(lines: [points], radius: coreRadius))
    }

    private func applyRing(_ result: RingResult) {
        guard let casingBuffers = result.casing, let coreBuffers = result.core,
              let casing = TubeMesh.mesh(from: casingBuffers),
              let core = TubeMesh.mesh(from: coreBuffers) else { return }
        meshCache[result.bucket] = (casing, core)
        if pendingBucket == result.bucket { pendingBucket = nil }
        conicCasing.model?.mesh = casing
        conicCore.model?.mesh = core
        appliedBucket = result.bucket
    }

    // MARK: Building

    private static func makeBead(name: String, accent: UIColor) -> ModelEntity {
        // Bright and solid, for the same reason the Bloom's value bead
        // is: this is the handle, not the surface the handle sits on.
        // A dark translucent pea 14 mm across, two metres away, against
        // a starfield, would be a target you could not find.
        let bead = ModelEntity(
            mesh: .generateSphere(radius: beadRadius),
            materials: [Materials.grip(emissive: accent, glow: 0.55)])
        bead.name = name
        // Collider EQUALS the visual radius. See the file header.
        bead.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: beadRadius)]))
        bead.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: name == nearBeadName
                ? "Closest point of the orbit. Pull to reshape it."
                : "Furthest point of the orbit. Pull to reshape it.")
        bead.components.set(accessibility)
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
