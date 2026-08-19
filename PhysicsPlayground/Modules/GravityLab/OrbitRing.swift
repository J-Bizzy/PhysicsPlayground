//
//  OrbitRing.swift
//  The selected body's osculating conic as a grabbable ring; math in PhysicsCore.ApsisFrame.
//  Meshes cache per eccentricity bucket, so per-frame cost is a transform write; never an anisotropic squash (it fattens the tube's cross-section).
//  Bead collider equals visual radius, counter-scaled against the 9× rig; the ring carries no collider.
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
    /// Eccentricity bucket width for the mesh cache.
    static let eccentricityStep = 0.03
    /// How many points a cached conic is sampled at.
    static let sampleCount = 256
    private static let coreRadius: Float = 0.0018

    private var meshCache: [Int: (casing: MeshResource, core: MeshResource)] = [:]
    private var appliedBucket: Int?
    private var pendingBucket: Int?
    private var pipeline: GeometryPipeline<RingJob, RingResult>?

    /// Abandons any ring rebuild in flight. See `GravityLabRenderer.teardown`.
    func teardown() { pipeline?.cancel() }

    /// Last-frame reachability per bead, for the reach hysteresis.
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
        // Cached mesh is built with p̂ = +x, ĥ = +y. The third column must be the cross of the first two so the matrix is a rotation, not a reflection: p̂ × ĥ = −q̂.
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
        // At/past parabolic shares one open-curve bucket: a hyperbola's drawn arc is dominated by clipping, not e.
        e >= 1 ? -1 : Int(max(e, 0) / eccentricityStep)
    }

    /// Canonical conic for a bucket: p = 1, periapsis +x, normal +y; everything else is scale + rotation.
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
        // Bright and solid: this is the handle, not the surface it sits on.
        let bead = ModelEntity(
            mesh: .generateSphere(radius: beadRadius),
            materials: [Materials.grip(emissive: accent, glow: 0.55)])
        bead.name = name
        // Collider EQUALS the visual radius.
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
