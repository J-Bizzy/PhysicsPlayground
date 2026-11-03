//
//  OrbitalMechanicsRenderer.swift
//  Renders the solar system diorama: Sun light, pooled planets, trails, prediction, arrows.
//
//  Frame-rate contract: pools built once; per-frame work is transform writes, plus the trails,
//  which are ring buffers rewritten in place (`TrailRibbons`, one mesh). The prediction and ring tubes are
//  computed on a GeometryPipeline worker; the main thread only uploads finished buffers.
//  Ticked from SceneEvents.Update — observation loops starve during grabs.
//

import Foundation
import PhysicsCore
import QuartzCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class OrbitalMechanicsRenderer {
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    /// Called from the SpaceView's `onDisappear`: subscriptions and pipeline jobs
    /// outlive this object and must be cancelled explicitly.
    func teardown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        predictionPipeline?.cancel()
        orbitRing.teardown()
    }

    /// The bodies already acknowledged with a pickup pulse — one flash per
    /// grab — and where each one's release tick plays.
    private var pulsedGrabs: [UUID: Entity] = [:]

    /// Where the system center sits in the room.
    static let systemPosition = SIMD3<Float>(0, 1.25, -1.2)

    /// Parent for the selected body's floating data panel; moved each render.
    let selectedAnchor = Entity()

    /// The scaled, placed root the bodies live under — blooms and wells convert through it.
    let systemRoot = Entity()
    /// Pausing materialises velocity/net-force arrows on every body.
    private let frozenVectors = FrozenVectors(budget: OrbitalMechanicsModel.bodyBudget * 2)

    // MARK: Predict-then-run — the ghost, its countdown, the verdict
    private let ghostEntity: ModelEntity = {
        let material = Materials.unlit(UIColor(white: 0.95, alpha: 1), opacity: 0.32)
        let ghost = ModelEntity(mesh: Primitives.sphere(radius: 0.035),
                                materials: [material])
        ghost.name = "prediction-ghost"
        ghost.components.set(InputTargetComponent())
        ghost.components.set(CollisionComponent(shapes: [Primitives.collisionSphere(radius: 0.055)]))
        ghost.components.set(HoverEffectComponent())
        ghost.isEnabled = false
        return ghost
    }()
    /// Aimed by dragging; its one hands-free verb is a step along its own radius.
    var onGhostAdjust: ((Double) -> Void)?

    /// The SpaceView's tap router, behind a box: the body pool is built in
    /// `init` before `self` exists, so closures capture the box.
    private final class TapRouter { var route: ((Entity) -> Void)? }
    private let tapRouter: TapRouter
    var onObjectTap: ((Entity) -> Void)? {
        get { tapRouter.route }
        set { tapRouter.route = newValue }
    }
    private var ghostCallout: Callout?
    /// Paragraph shown when a release parks a body at a Lagrange point — see `syncLagrangeCapture`.
    private(set) var lagrangeCallout: Callout?
    private var verdictLine = Entity()
    private var verdictCallout: Callout?
    private var verdictShownWall: Double?
    private var lastVerdict: OrbitalMechanicsModel.PredictionVerdict?

    /// The ghost while the clock runs; the guess-to-truth line when it stops.
    /// (Distinct from syncPrediction, the held-body trajectory preview.)
    private func syncPredictionGhost(_ model: OrbitalMechanicsModel) {
        let toDisplay = Float(model.simToDisplay)
        if let prediction = model.prediction {
            if ghostEntity.parent == nil { systemRoot.addChild(ghostEntity) }
            Fade.tick(ghostEntity, visible: true)
            ghostEntity.position = SIMD3<Float>(prediction.position) * toDisplay
            if ghostCallout == nil {
                let callout = Callout(color: UIColor(white: 0.95, alpha: 1),
                                      textSize: 0.02, offset: SIMD3(0, 0.08, 0))
                callout.setAccessibilityName("Prediction")
                systemRoot.addChild(callout.root)
                ghostCallout = callout
            }
            ghostCallout.map { Fade.tick($0.root, visible: true) }
            ghostCallout?.anchor(at: ghostEntity.position)
            let daysLeft = max(prediction.resolvesAt - model.simulatedDays, 0)
            // Days in words, as More's Elapsed counts them.
            ghostCallout?.setText("your guess · "
                                  + PhysicsFormat.count(daysLeft, singular: "day", plural: "days"))
        } else {
            // Faded, not switched (2026-11-02): a guess resolved, or gone
            // with its planet, leaves as the arrows do.
            Fade.tick(ghostEntity, visible: false)
            ghostCallout.map { Fade.tick($0.root, visible: false) }
        }

        if let verdict = model.predictionVerdict {
            if verdict != lastVerdict {
                lastVerdict = verdict
                verdictShownWall = CACurrentMediaTime()
                if verdictLine.parent == nil { systemRoot.addChild(verdictLine) }
                verdictLine.children.forEach { $0.removeFromParent() }
                let guess = SIMD3<Float>(verdict.guess) * toDisplay
                let actual = SIMD3<Float>(verdict.bodyPosition) * toDisplay
                if let tube = TubeMesh.tube(
                    lines: [[guess, actual]], radius: 0.0022, sides: 4) {
                    let material = Materials.unlit(UIColor(white: 0.95, alpha: 1), opacity: 0.7)
                    verdictLine.addChild(ModelEntity(mesh: tube, materials: [material]))
                }
                if verdictCallout == nil {
                    let callout = Callout(color: UIColor(white: 0.95, alpha: 1),
                                          textSize: 0.022, offset: SIMD3(0, 0.09, 0))
                    callout.setAccessibilityName("Prediction result")
                    systemRoot.addChild(callout.root)
                    verdictCallout = callout
                }
                verdictCallout?.anchor(at: (guess + actual) / 2)
                let miss = PhysicsFormat.measurement(verdict.missAU, "AU",
                                                     decimals: 2)
                verdictCallout?.setText(verdict.missAU < 0.1
                    ? "off by \(miss) — called it" : "off by \(miss)")
            }
            // Eight seconds of reading time, then the verdict retires.
            let shown = verdictShownWall.map { CACurrentMediaTime() - $0 } ?? 0
            let visible = shown < 8
            // The model's comment always said the renderer fades it out; now it does.
            Fade.tick(verdictLine, visible: visible, duration: 0.6)
            verdictCallout.map { Fade.tick($0.root, visible: visible, duration: 0.6) }
        } else {
            Fade.tick(verdictLine, visible: false)
            verdictCallout.map { Fade.tick($0.root, visible: false) }
        }
    }

    // MARK: Kepler sweep — two gold sectors and their areas
    private let sweepCurrentEntity = ModelEntity()
    private let sweepHeldEntity = ModelEntity()
    private var sweepCurrentLabel: Callout?
    private var sweepHeldLabel: Callout?
    private static let sweepGold = UIColor(red: 1.0, green: 0.80, blue: 0.30, alpha: 1)
    /// Pure view transform between scene root and system: the two-hand rig drives this and
    /// nothing else, so the simulation keeps running in true SI units while apparent size changes.
    let viewRoot = Entity()
    /// Refreshed per render.
    private var scale: Float = 1

    private let bodyPool: EntityPool<ModelEntity>
    private var bodyMaterialKeys: [String]
    /// Which body each pooled slot is named for. The entity `.name` must be the uuidString
    /// (manipulation events resolve by it); compare UUIDs, not strings — `uuidString` allocates.
    private var bodySlotIDs: [UUID?]
    /// The scale each pooled body's touch target was last sized for.
    private var bodyColliderScales: [Int: Float] = [:]
    private var bodyNames: [String]
    private static let baseBodyRadius: Float = 0.05

    /// Sun halo and the reference radius its scale is expressed against
    /// (`sunGlow.scale = displayRadius / glowReferenceRadius`). Named because `calloutAnchor` must clear it.
    static let glowBaseRadius: Double = 0.105
    static let glowReferenceRadius: Double = 0.075

    /// One ribbon slot per body, keyed by body id: a merge frees the dead
    /// body's slot the frame its id goes, so no slot draws a dead path. All
    /// the slots are parts of one mesh, written once a frame.
    private let trailsRoot = Entity()
    private var ribbons: TrailRibbons?
    private var ribbonCount: Int { ribbons?.slots ?? 0 }
    private var ribbonSlots: [UUID: Int] = [:]
    private var ribbonGenerations: [UInt32?] = []
    private var ribbonRadii: [Float] = []
    private var ribbonHeads: [SIMD3<Float>] = []
    private var ribbonMaterialKeys: [String] = []
    private var ribbonScrubNonce = -1
    /// When the trail mesh last went to the renderer, wall-clock seconds.
    private var lastTrailCommit = -Double.infinity
    /// Per slot: the head the mesh was last written with, and the thin unit
    /// cylinder that carries the trail on from it to the body each frame.
    private var committedHeads: [SIMD3<Float>?] = []
    private var leaders: [ModelEntity] = []
    /// The opacity ramp every ribbon reads; nil until the loader delivers it.
    private var fadeRamp: TextureResource?
    private var predictionPipeline: GeometryPipeline<PredictionJob, PredictionBuffers>?
    private var predictionActive = false

    private let sunLight = Entity()
    private var sunGlow: ModelEntity!
    private let audioEmitter = Entity()
    private var lastSoundID = 0
    private var appliedTextureVersion = -1
    private let predictionEntity = ModelEntity()
    private let predictionMaterial: UnlitMaterial
    /// Cased with `Materials.contrastLine` like Projectiles' arc — same token, same treatment.
    /// Trails are deliberately left uncased: sixteen of them rebuild as bodies move.
    private let predictionCasingEntity = ModelEntity()
    private let predictionCasingMaterial: UnlitMaterial
    /// Shared by the core tube and `casingRadius`, so the two cannot change apart.
    private nonisolated static let predictionRadius: Float = 0.002
    private let flashEntity: ModelEntity

    private struct Arrow {
        let container: Entity
        let shaft: ModelEntity
        let head: ModelEntity
    }
    private var velocityArrow: Arrow!
    private var forceArrow: Arrow!

    private var frameCounter = 0
    private var lastMergeNonce = 0

    init() {
        // First, and as a local — see `TapRouter`.
        let router = TapRouter()
        tapRouter = router

        systemRoot.position = Self.systemPosition
        viewRoot.addChild(systemRoot)
        root.addChild(viewRoot)

        // Bodies.
        let bodyMesh = Primitives.sphere(radius: Self.baseBodyRadius)
        bodyPool = EntityPool(budget: OrbitalMechanicsModel.bodyBudget) { container in
            let sphere = ModelEntity(
                mesh: bodyMesh,
                materials: [Materials.machined(.white, roughness: 0.6)]
            )
            // 1.15×: a larger factor makes an apsis bead near the surface unpinchable.
            Grabbable.configureTouchTarget(
                sphere, collisionRadius: Self.baseBodyRadius * 1.15,
                activate: { [weak sphere] in
                    guard let sphere else { return }
                    router.route?(sphere)
                })
            // Renamed to the body it carries whenever the slot changes hands.
            SpatialActions.describe(sphere, label: "Celestial body")
            container.addChild(sphere)
            return sphere
        }
        bodyMaterialKeys = Array(repeating: "", count: bodyPool.budget)
        bodySlotIDs = Array(repeating: nil, count: bodyPool.budget)
        bodyNames = Array(repeating: "", count: bodyPool.budget)
        systemRoot.addChild(bodyPool.root)
        systemRoot.addChild(frozenVectors.root)
        for sector in [sweepCurrentEntity, sweepHeldEntity] {
            sector.isEnabled = false
            systemRoot.addChild(sector)
        }

        // Warm light following the heaviest body. Attenuation 40 m: Neptune's ring is 15 m
        // at 1×, and the one cue the scene cannot lose is which side of a planet faces the Sun.
        sunLight.components.set(PointLightComponent(
            color: UIColor(red: 1.0, green: 0.9, blue: 0.75, alpha: 1),
            intensity: 12_000,
            attenuationRadius: 40
        ))
        systemRoot.addChild(sunLight)

        // Light, not a surface: writing depth, the glow cut its disc out of
        // the 16 m shell (an undimmed room round the Sun) and out of deep
        // space's sky. A copy, so the shared recipe keeps its depth.
        var glowMaterial = Materials.unlit(UIColor(red: 1.0, green: 0.82, blue: 0.5, alpha: 1), opacity: 0.16)
        glowMaterial.writesDepth = false
        sunGlow = ModelEntity(mesh: Primitives.sphere(radius: Float(Self.glowBaseRadius)),
                              materials: [glowMaterial])
        systemRoot.addChild(sunGlow)

        audioEmitter.components.set(SpatialAudioComponent())
        systemRoot.addChild(audioEmitter)
        CelestialTextures.warmUp()

        // Trails: one ribbon slot per body, rewritten in place.
        systemRoot.addChild(trailsRoot)
        let trails = TrailRibbons(slots: OrbitalMechanicsModel.bodyBudget, capacity: OrbitTrail.capacity)
        if let trails { trailsRoot.addChild(trails.entity) }
        ribbons = trails
        let slots = trails?.slots ?? 0
        ribbonGenerations = Array(repeating: nil, count: slots)
        ribbonRadii = Array(repeating: 0, count: slots)
        ribbonHeads = Array(repeating: .zero, count: slots)
        ribbonMaterialKeys = Array(repeating: "", count: slots)
        committedHeads = Array(repeating: nil, count: slots)
        let leaderMesh = Primitives.cylinder(height: 1, radius: 1)
        var leaderPool: [ModelEntity] = []
        for _ in 0..<slots {
            let leader = ModelEntity(mesh: leaderMesh, materials: [Materials.unlit(.white)])
            leader.isEnabled = false
            trailsRoot.addChild(leader)
            leaderPool.append(leader)
        }
        leaders = leaderPool

        // Held-body orbit prediction: two passes from one recipe so the casing and core
        // opacities stay the house numbers.
        let (predictionCasing, predictionCore) = Materials.contrastLine(
            DesignTokens.Palette.predictedArcUI, coreOpacity: 0.55)
        self.predictionMaterial = predictionCore
        self.predictionCasingMaterial = predictionCasing
        // Casing first, so the core draws over it.
        systemRoot.addChild(predictionCasingEntity)
        systemRoot.addChild(predictionEntity)

        // Merge flash.
        let flashMaterial = Materials.unlit(.white, opacity: 0.7)
        flashEntity = ModelEntity(mesh: Primitives.sphere(radius: 0.03), materials: [flashMaterial])
        flashEntity.isEnabled = false
        systemRoot.addChild(flashEntity)

        // Vector arrows on the selected body.
        velocityArrow = Self.makeArrow(color: DesignTokens.Palette.velocityVectorUI)
        forceArrow = Self.makeArrow(color: DesignTokens.Palette.forceVectorUI)
        for arrow in [velocityArrow!, forceArrow!] {
            systemRoot.addChild(arrow.container)
        }

        selectedAnchor.components.set(BillboardComponent())
        systemRoot.addChild(selectedAnchor)

        // Lagrange point markers; positions written every render.
        let markerMesh = Primitives.sphere(radius: 0.009)
        let markerMaterial = Materials.unlit(DesignTokens.Palette.targetUI, opacity: 0.85)
        for name in ["L1", "L2", "L3", "L4", "L5"] {
            let marker = ModelEntity(mesh: markerMesh, materials: [markerMaterial])
            // House dark plate behind the name; the pivot lifts to the run's centre.
            let label = BackedLabel(size: 0.02)
            label.setText(name, color: DesignTokens.Palette.targetUI)
            lagrangeLabels.append(label)
            let labelPivot = Entity()
            labelPivot.components.set(BillboardComponent())
            labelPivot.position = [0, 0.024, 0]
            labelPivot.addChild(label.root)
            marker.addChild(labelPivot)
            marker.isEnabled = false
            SpatialActions.describe(marker, label: "Lagrange point \(name)")
            lagrangeMarkers.append(marker)
            systemRoot.addChild(marker)
        }

        systemRoot.addChild(orbitRing.root)
        scaleReadout.isEnabled = false
        root.addChild(scaleReadout)

        predictionPipeline = GeometryPipeline(
            compute: { Self.computePrediction($0) },
            apply: { [weak self] in self?.applyPrediction($0) }
        )

        // Last: `self` is unavailable until every stored property is set.
        SpatialActions.attach(
            to: ghostEntity, label: "Predicted path",
            adjust: { [weak self] steps in self?.onGhostAdjust?(steps) })
        // The ribbons wear a flat colour until the ramp arrives, then fade.
        Task { [weak self] in
            let ramp = await Materials.fadeRamp()
            self?.fadeRamp = ramp
        }
    }

    private var lagrangeMarkers: [ModelEntity] = []
    /// Retains the markers' BackedLabels (the entity graph holds only their roots).
    private var lagrangeLabels: [BackedLabel] = []

    // MARK: The orbit ring — the selected body's conic, as an object
    // Under `systemRoot`: a hand arrives via `displayPoint(fromWorld:)`, and an anchor
    // parented in another frame lands nowhere near the thing it belongs to.
    private let orbitRing = OrbitRing(
        accent: UIColor(DesignTokens.Palette.gravityAccent))

    /// Which apsis bead an entity is, if any — the renderer owns the beads.
    func apsis(for entity: Entity) -> Apsis? { orbitRing.apsis(for: entity) }

    /// Forwards a VoiceOver step on an apsis bead — see `OrbitRing.onAdjust`.
    var onApsisAdjust: ((Apsis, Double) -> Void)? {
        get { orbitRing.onAdjust }
        set { orbitRing.onAdjust = newValue }
    }

    func beadDisplayPoint(_ apsis: Apsis) -> SIMD3<Double> {
        orbitRing.beadDisplayPoint(apsis)
    }

    /// The viewer, for the beads' reach rule — already converted into the system's own frame.
    var viewerInSystem: SIMD3<Float>?
    /// The two-hand rig's live scale, so the beads can compensate for it.
    var rigScale: Float = 1

    /// Everything read rather than simulated holds its size:
    /// counter-scaling by 1/rig cancels the rig exactly.
    private func applyRigCompensation() {
        let compensation = SIMD3<Float>(repeating: 1 / max(rigScale, 0.001))
        for label in bodyLabels { label.scale = compensation }
        for callout in [ghostCallout, verdictCallout,
                        sweepCurrentLabel, sweepHeldLabel] {
            callout?.root.scale = compensation
        }
        for instrument in rigCompensatedInstruments {
            instrument.scale = compensation
        }
    }

    /// Instruments under `systemRoot` that must keep size and place — chiefly the spawn well.
    private var rigCompensatedInstruments: [Entity] = []

    func compensateForRig(_ entity: Entity) {
        rigCompensatedInstruments.append(entity)
    }

    // MARK: The scale readout
    // Under `root`, so the readout does not resize with the thing it reports on.

    private let scaleReadout = Entity()
    private var scaleReadoutText: String?
    private var scaleReadoutBuiltFrame = 0

    /// Shows "3.4x" beside the clock bank, or nothing at 1x. The plate is
    /// extruded text, so mid-gesture it is rebuilt at most every eight
    /// frames; the value it settles on is drawn within the same eight.
    func showScaleReadout(_ label: String?, anchor: SIMD3<Float>) {
        guard let label else {
            scaleReadout.isEnabled = false
            return
        }
        scaleReadout.isEnabled = true
        scaleReadout.position = anchor
        if scaleReadoutText != label, frameCounter - scaleReadoutBuiltFrame >= 8 || scaleReadoutText == nil {
            scaleReadoutText = label
            scaleReadoutBuiltFrame = frameCounter
            scaleReadout.children.forEach { $0.removeFromParent() }
            let plate = HubScene.namePlate(
                label, accent: UIColor(DesignTokens.Palette.gravityAccent),
                size: PlateStyle.exhibitLabelSize)
            plate.components.set(BillboardComponent())
            scaleReadout.addChild(plate)
        }
    }

    /// The paragraph explaining a Lagrange capture. It follows the body: L1–L3 saddles slide off, L4/L5 hold — the callout tracks whichever, so the text's prediction plays out in view.
    private func syncLagrangeCapture(_ model: OrbitalMechanicsModel) {
        guard let name = model.capturedPointName,
              let text = OrbitalMechanicsModel.lagrangeExplanations[name],
              let id = model.capturedBodyID,
              let body = model.bodies.first(where: { $0.id == id }) else {
            lagrangeCallout?.isEnabled = false
            return
        }
        if lagrangeCallout == nil {
            let callout = Callout(color: Self.sweepGold, textSize: 0.020,
                                  offset: SIMD3(0, 0.10, 0))
            // A paragraph, so it wraps — every other callout here is a number.
            callout.wrapWidth = 0.46
            callout.setAccessibilityName("Lagrange point \(name)")
            systemRoot.addChild(callout.root)
            lagrangeCallout = callout
        }
        lagrangeCallout?.isEnabled = true
        lagrangeCallout?.anchor(at: calloutAnchor(for: body, in: model))
        lagrangeCallout?.setText(text)
    }

    /// Where the paragraph stands: on the body, pushed forward along the view ray far enough to clear the star's halo (inner planets' L-points sit inside the star otherwise).
    private func calloutAnchor(for body: OrbitalMechanicsModel.OrbitingBody,
                               in model: OrbitalMechanicsModel) -> SIMD3<Float> {
        let scale = Float(model.simToDisplay)
        let seat = SIMD3<Float>(body.body.position) * scale
        guard let viewer = viewerInSystem, let star = model.primaryBody else {
            return seat
        }
        let centre = SIMD3<Float>(star.body.position) * scale
        // Halo reach derived from the same two numbers that build it, so it stays correct if either moves.
        let halo = Float(star.displayRadius)
            * Float(Self.glowBaseRadius / Self.glowReferenceRadius)

        // Solve for the plane in front of the star's near surface rather than nudging toward the reader.
        let axis = viewer - centre
        let reach = length(axis)
        guard reach > 1e-4 else { return seat }
        let toward = axis / reach
        let clearance = halo + 0.05
        let depth = dot(seat - centre, toward)
        guard depth < clearance else { return seat }
        // …but never into the reader's face: stop short of arm's length.
        let room = max(0, reach - 0.25 - depth)
        return seat + toward * min(clearance - depth, room)
    }

    private func syncOrbitRing(_ model: OrbitalMechanicsModel) {
        guard let selected = model.selectedBody,
              let primary = model.ringPrimary(for: selected),
              let frame = model.orbitFrame(for: selected.id) else {
            orbitRing.update(frame: nil, primaryDisplay: .zero,
                             simToDisplay: model.simToDisplay, rigScale: rigScale,
                             occluders: [], head: viewerInSystem)
            return
        }
        // In the ring's frame, not the system's: `OrbitRing.root` sits on the primary, so occluders must be offset by the primary's own position (a Twin-suns primary is off origin).
        let primaryDisplay = SIMD3<Float>(primary.body.position) * scale
        let occluders = model.bodies.map {
            (center: SIMD3<Float>($0.body.position) * scale - primaryDisplay,
             radius: Float($0.displayRadius))
        }
        orbitRing.update(
            frame: frame,
            primaryDisplay: primaryDisplay,
            simToDisplay: model.simToDisplay,
            rigScale: rigScale,
            occluders: occluders,
            head: viewerInSystem)
    }


    private static func makeArrow(color: UIColor) -> Arrow {
        // Clean bright shaft, glossy self-lit head that catches the key light.
        let shaftMaterial = UnlitMaterial(color: color)
        let headMaterial = Materials.energized(color, roughness: 0.2, glow: 0.35)
        let shaft = ModelEntity(
            mesh: Primitives.cylinder(height: 0.1, radius: 0.0035), materials: [shaftMaterial])
        let head = ModelEntity(
            mesh: Primitives.cone(height: 0.03, radius: 0.011), materials: [headMaterial])
        let container = Entity()
        container.addChild(shaft)
        container.addChild(head)
        container.isEnabled = false
        return Arrow(container: container, shaft: shaft, head: head)
    }

    // MARK: Per-frame tick (from SceneEvents.Update)

    /// Room coordinates → display coordinates relative to the system centre.
    /// Goes through the actual transform so a scaled/rotated view rig is inverted exactly — a constant offset would fling a grabbed planet in a zoomed view.
    func displayPoint(fromWorld world: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3<Double>(systemRoot.convert(position: world, from: nil))
    }

    // MARK: The orbital chord — Kepler's third law, heard

    /// One voice per body, pitched by its orbital period — Kepler's T² ∝ a³ heard as a chord (Earth's year the reference note).
    private var chordVoices: [UUID: ToneVoice] = [:]
    private var chordEmitters: [UUID: Entity] = [:]

    /// The note each body is currently singing, so per-frame work is "keep singing it from over there". See `tickOrbitalChord`.
    private var chordNotes: [UUID: (pitch: Double, loudness: Double)] = [:]

    /// How often orbital periods are re-derived — a property of the whole orbit, not of this instant.
    private static let chordAnalysisInterval = 12

    /// The frozen readout: every body's velocity and the net gravitational pull on it (the integrator's own law). The O(n²) sum runs only while the arrows are shown.
    private static func frozenSamples(model: OrbitalMechanicsModel) -> [FrozenVectors.Sample] {
        let bodies = model.bodies.map(\.body)
        guard bodies.count > 1 else { return [] }
        let toDisplay = Float(model.simToDisplay)
        let g = model.effectiveG

        // The integrator's own law, softening included — not a second copy of it.
        let accelerations = NBody.accelerations(
            bodies: bodies, gravitationalConstant: g, softening: model.softeningRadii)
        let forces = zip(bodies, accelerations).map { $0.mass * $1 }
        let maxSpeed = bodies.map { simd_length($0.velocity) }.max() ?? 1
        let maxForce = forces.map(simd_length).max() ?? 1

        var samples: [FrozenVectors.Sample] = []
        for (index, body) in bodies.enumerated() {
            let position = SIMD3<Float>(body.position) * toDisplay
            let speed = simd_length(body.velocity)
            if speed > 1e-9, maxSpeed > 0 {
                samples.append(.init(
                    position: position,
                    direction: SIMD3<Float>(body.velocity / speed),
                    // sqrt spreads the slow outer planets off the floor of the scale.
                    magnitude01: Float((speed / maxSpeed).squareRoot()),
                    kind: .velocity))
            }
            let force = simd_length(forces[index])
            if force > 0, maxForce > 0 {
                samples.append(.init(
                    position: position,
                    direction: SIMD3<Float>(forces[index] / force),
                    magnitude01: Float((force / maxForce).squareRoot()),
                    kind: .force))
            }
        }
        return samples
    }

    /// Kepler's second law, painted: the sector being swept now in bright
    /// gold, the last completed window held in dim gold beside it, each
    /// engraved with its area. Both sectors come from the integrated
    /// samples.
    private func syncKeplerSweep(_ model: OrbitalMechanicsModel) {
        guard model.keplerSweepOn, let primary = model.primaryBody else {
            sweepCurrentEntity.isEnabled = false
            sweepHeldEntity.isEnabled = false
            sweepCurrentLabel?.isEnabled = false
            sweepHeldLabel?.isEnabled = false
            return
        }
        let toDisplay = Float(model.simToDisplay)
        let apex = SIMD3<Float>(primary.body.position) * toDisplay
        let au = CelestialBody.astronomicalUnit

        func show(_ entity: ModelEntity, label: inout Callout?,
                  arc: [SIMD3<Double>], area: Double, material: UnlitMaterial) {
            // One sample per physics frame is far finer than the sector needs;
            // thin it before the mesh so the main-actor build stays small.
            let outline = TubeMesh.decimated(
                [arc.map { apex + SIMD3<Float>($0) * toDisplay }],
                spacing: 0.003, maximumTurn: .pi / 90).first ?? []
            guard outline.count >= 2,
                  let mesh = Self.sectorMesh(apex: apex, arc: outline) else {
                entity.isEnabled = false
                label?.isEnabled = false
                return
            }
            // The mesh changes each redraw; the two materials never do, so they
            // are banked as constants.
            entity.model = ModelComponent(mesh: mesh, materials: [material])
            entity.isEnabled = true

            if label == nil {
                let callout = Callout(color: Self.sweepGold,
                                      textSize: 0.018, offset: SIMD3(0, 0.06, 0))
                callout.setAccessibilityName("Area swept")
                systemRoot.addChild(callout.root)
                label = callout
            }
            let mid = arc[arc.count / 2]
            label?.isEnabled = true
            label?.anchor(at: apex + SIMD3<Float>(mid) * toDisplay * 0.6)
            label?.setText(PhysicsFormat.measurement(area / (au * au), "AU²", decimals: 2))
        }

        if let current = model.sweepCurrentGeometry() {
            show(sweepCurrentEntity, label: &sweepCurrentLabel,
                 arc: current.arc, area: current.area,
                 material: Self.sweepCurrentMaterial)
        } else {
            sweepCurrentEntity.isEnabled = false
            sweepCurrentLabel?.isEnabled = false
        }
        show(sweepHeldEntity, label: &sweepHeldLabel,
             arc: model.sweepHeldArc, area: model.sweepHeldArea,
             material: Self.sweepHeldMaterial)
    }

    /// The sweep's two materials, built once: the accruing sector and the
    /// held one differ only in opacity. A triangle fan from the apex, both
    /// windings, so the sector reads from either side of the plane.
    private static let sweepCurrentMaterial = sweepMaterial(opacity: 0.30)
    private static let sweepHeldMaterial = sweepMaterial(opacity: 0.14)

    private static func sweepMaterial(opacity: Float) -> UnlitMaterial {
        let material = Materials.unlit(sweepGold, opacity: opacity)
        return material
    }

    private static func sectorMesh(apex: SIMD3<Float>,
                                   arc: [SIMD3<Float>]) -> MeshResource? {
        guard arc.count >= 2 else { return nil }
        var positions: [SIMD3<Float>] = [apex]
        positions.append(contentsOf: arc)
        var indices: [UInt32] = []
        for index in 1..<UInt32(arc.count) {
            indices.append(contentsOf: [0, index, index + 1])
            indices.append(contentsOf: [0, index + 1, index])
        }
        var descriptor = MeshDescriptor(name: "kepler-sector")
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private func tickOrbitalChord(_ model: OrbitalMechanicsModel) {
        guard model.playOrbitalChord else {
            chordVoices.values.forEach { $0.mute() }
            chordNotes.removeAll()
            return
        }

        // `model.readout(for:)` sums potential energy over every body, so the
        // pitch is re-derived a few times a second rather than every frame;
        // position is tracked continuously.
        if chordNotes.isEmpty || frameCounter % Self.chordAnalysisInterval == 0 {
            // Earth's year is the anchor, so the reference note is fixed
            // and the chord doesn't transpose as bodies come and go.
            let referencePeriod = 365.25
            var fresh: [UUID: (pitch: Double, loudness: Double)] = [:]
            for orbiting in model.bodies {
                guard let readout = model.readout(for: orbiting),
                      let periodDays = readout.periodDays, readout.isBound else { continue }
                // Heavier bodies sing louder — the chord is dominated by
                // the planets that dominate the system.
                let loudness = Sonification.loudness(
                    log10(max(orbiting.body.mass, 1)) - 20, full: 8, knee: 1.0)
                fresh[orbiting.id] = (
                    Sonification.pitch(forPeriodSeconds: periodDays,
                                       referencePeriod: referencePeriod),
                    max(loudness, 0.12))
            }
            chordNotes = fresh
        }

        var live = Set<UUID>()
        for orbiting in model.bodies {
            guard let note = chordNotes[orbiting.id] else { continue }
            live.insert(orbiting.id)

            let emitter: Entity
            if let existing = chordEmitters[orbiting.id] {
                emitter = existing
            } else {
                emitter = Entity()
                systemRoot.addChild(emitter)
                chordEmitters[orbiting.id] = emitter
                chordVoices[orbiting.id] = ToneVoice(on: emitter, range: (-64)...(-30))
            }
            // Sounds from where the body is, every frame: this is what attaches the
            // chord to the objects.
            emitter.position = SIMD3<Float>(orbiting.body.position * model.simToDisplay)
            guard chordVoices[orbiting.id]?.start() == true else { continue }

            chordVoices[orbiting.id]?.update(pitchHz: note.pitch,
                                             loudness: note.loudness,
                                             smoothing: 0.08)
        }
        // A body that merged, escaped, or was deleted goes silent.
        for (id, voice) in chordVoices where !live.contains(id) {
            voice.mute()
        }
    }

    /// The prediction ghost while a hand moves it: the glow and the ticks a
    /// body answers a hand with (2026-11-02).
    let carried = Grasp.Carried()

    func tick(_ model: OrbitalMechanicsModel) {
        carried.find(under: root)
        frameCounter &+= 1
        tickOrbitalChord(model)
        if frameCounter % 12 == 0 { syncKeplerSweep(model) }
        syncPredictionGhost(model)
        // This tick has no dt of its own; the fade only needs a clock.
        frozenVectors.update(frozen: model.isPaused, dt: 1.0 / 90) {
            Self.frozenSamples(model: model)
        }
        scale = Float(model.simToDisplay)

        // Fresh procedural textures arrived: reapply body materials.
        if appliedTextureVersion != CelestialTextures.version {
            appliedTextureVersion = CelestialTextures.version
            bodyMaterialKeys = Array(repeating: "", count: bodyPool.budget)
        }

        // Spatial sounds requested by the model.
        if let event = model.soundEvent, event.id != lastSoundID {
            lastSoundID = event.id
            audioEmitter.position = SIMD3<Float>(event.position) * scale
            SoundPalette.play(event.kind, on: audioEmitter, volume: event.volume)
        }

        syncBodies(model)
        syncTrails(model)
        syncPrediction(model)
        syncVectors(model)
        syncMergeFlash(model)
        syncOrbitRing(model)
        syncLagrangeCapture(model)
        applyRigCompensation()
        syncLagrangeMarkers(model)
    }

    // MARK: Idle motion (ticked every frame by the space view, apart from the physics)

    /// Every body turns slowly on its axis — presentation, but it makes the
    /// textures live.
    func tickIdleMotion(dt: Double, model: OrbitalMechanicsModel) {
        // Pause freezes everything in time — spins included. Reduce Motion
        // stills them too: the turn is presentation, not physics.
        guard !model.isPaused, !Motion.isReduced else { return }
        for (index, slot) in bodyPool.slots.enumerated()
        where index < model.bodies.count {
            let rate: Float = model.bodies[index].body.name.hasPrefix("Sun") ? 0.06 : 0.22
            slot.payload.orientation = simd_quatf(angle: rate * Float(dt), axis: [0, 1, 0])
                * slot.payload.orientation
        }
    }

    private func syncLagrangeMarkers(_ model: OrbitalMechanicsModel) {
        let points = model.lagrangePoints
        for (index, marker) in lagrangeMarkers.enumerated() {
            guard index < points.count else {
                Fade.tick(marker, visible: false)
                continue
            }
            Fade.tick(marker, visible: true)
            marker.position = SIMD3<Float>(points[index].position) * scale
        }
    }

    /// Billboarded name tags riding above the bodies — you should never
    /// have to guess which dot is Mars.
    private var bodyLabels: [Entity] = []
    /// The planet names on `BackedLabel`, the same house plate the Lagrange
    /// markers wear.
    private var bodyLabelPlates: [BackedLabel] = []

    private func ensureLabel(_ index: Int) {
        while bodyLabels.count <= index {
            let holder = Entity()
            let pivot = Entity()
            pivot.components.set(BillboardComponent())
            holder.addChild(pivot)
            let plate = BackedLabel(size: 0.022)
            pivot.addChild(plate.root)
            holder.isEnabled = false
            systemRoot.addChild(holder)
            bodyLabels.append(holder)
            bodyLabelPlates.append(plate)
        }
    }

    private func syncBodies(_ model: OrbitalMechanicsModel) {
        // A body deleted or merged away fades where it was; its slot goes
        // straight on to show the next body.
        let live = Set(model.bodies.map(\.id))
        for (index, slot) in bodyPool.slots.enumerated() {
            if let shown = bodySlotIDs[index], !live.contains(shown) {
                Retire.copy(of: slot.entity)
                bodySlotIDs[index] = nil
            }
        }
        for (index, slot) in bodyPool.slots.enumerated() {
            guard index < model.bodies.count else {
                slot.entity.isEnabled = false
                continue
            }
            let orbiting = model.bodies[index]
            slot.entity.isEnabled = true
            if bodySlotIDs[index] != orbiting.id {
                bodySlotIDs[index] = orbiting.id
                slot.payload.name = orbiting.id.uuidString
            }
            if bodyNames[index] != orbiting.body.name {
                bodyNames[index] = orbiting.body.name
                SpatialActions.describe(slot.payload, label: orbiting.body.name)
            }
            ensureLabel(index)
            // The material key is the body's name, so this gate is "has this slot
            // changed bodies"; the label belongs inside it.
            if bodyMaterialKeys[index] != orbiting.body.name {
                bodyMaterialKeys[index] = orbiting.body.name
                slot.payload.model?.materials = [material(for: orbiting.body.name)]
            }
            // Every frame, outside the gate: free when unchanged, and a name
            // the rate limit held back (a slot that changed bodies twice in
            // a beat) lands on the next frame instead of never.
            bodyLabelPlates[index].setText(orbiting.body.name, color: .white)
            bodyLabels[index].isEnabled = true
            bodyLabels[index].position = SIMD3<Float>(orbiting.body.position) * scale
                + SIMD3(0, Float(orbiting.displayRadius) + 0.028, 0)
            let bodyScale = Float(orbiting.displayRadius) / Self.baseBodyRadius
            slot.entity.scale = SIMD3<Float>(repeating: bodyScale)
            // Re-sized with the body so its reach stays constant; change-gated
            // because it allocates a `ShapeResource`. On `slot.payload`, the sphere
            // carrying the input target, not the container.
            if abs((bodyColliderScales[index] ?? -1) - bodyScale) > 1e-4 {
                bodyColliderScales[index] = bodyScale
                slot.payload.components.set(CollisionComponent(shapes: [
                    Primitives.collisionSphere(radius: Grabbable.sphereTargetRadius(
                        baseRadius: Self.baseBodyRadius, scale: bodyScale)),
                ]))
            }

            // A grab is acknowledged once, read off the model (`heldBodyIDs`, one
            // body in each hand since 2026-11-02); until 2026-10-14 this keyed on
            // a flag nothing set. The model carries a held body, so its
            // transform is written like any other.
            if model.heldBodyIDs.contains(orbiting.id), pulsedGrabs[orbiting.id] == nil {
                // Live while held: the glow stays until that hand lets go.
                pulsedGrabs[orbiting.id] = slot.entity
                LiveGlow.set(true, on: slot.entity)
                SoundPalette.play(.grabTick, on: slot.entity, volume: 0.2)
            }
            slot.entity.position = SIMD3<Float>(orbiting.body.position) * scale
            slot.payload.position = .zero
        }
        for index in model.bodies.count..<bodyPool.budget {
            bodyPool.slots[index].entity.isEnabled = false
            if index < bodyLabels.count { bodyLabels[index].isEnabled = false }
        }
        for (id, entity) in pulsedGrabs where !model.heldBodyIDs.contains(id) {
            pulsedGrabs[id] = nil
            LiveGlow.set(false, on: entity)
            SoundPalette.play(.releaseTick, on: entity, volume: 0.18)
        }

        if let primary = model.primaryBody {
            sunLight.position = SIMD3<Float>(primary.body.position) * scale
            let isSun = primary.body.name.hasPrefix("Sun")
            sunGlow.isEnabled = isSun
            if isSun {
                sunGlow.position = sunLight.position
                sunGlow.scale = SIMD3(
                    repeating: Float(primary.displayRadius / Self.glowReferenceRadius))
            }
        }

        // Data-panel anchor floats above the selected body.
        if let selected = model.selectedBody {
            selectedAnchor.isEnabled = true
            selectedAnchor.position = SIMD3<Float>(selected.body.position) * scale
                + SIMD3(0, Float(selected.displayRadius) + 0.12, 0)
        } else {
            selectedAnchor.isEnabled = false
        }
    }

    /// A world as the well shows it: an Earth-textured sphere at the size a
    /// pulled body arrives at.
    static func worldPreview() -> Entity {
        let sphere = ModelEntity(
            mesh: Primitives.sphere(radius: 0.030),
            materials: [staticMaterial(for: "Earth")])
        // A slight tilt, so the texture's poles are not dead-on and the
        // thing reads as a globe rather than a flat disc.
        sphere.orientation = simd_quatf(angle: 0.35, axis: simd_normalize(SIMD3(0.3, 0, 1)))
        return sphere
    }

    /// `material(for:)` without an instance — the well builds its
    /// preview before any renderer exists.
    private static func staticMaterial(for name: String) -> RealityKit.Material {
        if let texture = CelestialTextures.texture(for: name) {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = 0.7
            material.metallic = 0.0
            return material
        }
        return Materials.machined(DesignTokens.Palette.celestialUI(name))
    }

    private func material(for name: String) -> RealityKit.Material {
        let texture = CelestialTextures.texture(for: name)
        if name.hasPrefix("Sun") {
            // Unlit = self-luminous against the room.
            var material = UnlitMaterial(color: DesignTokens.Palette.celestialUI(name))
            if let texture {
                material.color = .init(tint: .white, texture: .init(texture))
            }
            return material
        }
        if let texture {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = 0.7
            material.metallic = 0.0
            return material
        }
        return Materials.machined(
            DesignTokens.Palette.celestialUI(name), roughness: 0.55)
    }

    // MARK: Trails — one ribbon per body, rewritten in place

    /// The tube's radius in display units: 1.2 mm in the room at any zoom,
    /// bucketed by 12 % so a two-hand zoom does not rewrite every ribbon's
    /// shape every frame.
    nonisolated static func trailRadius(rigScale: Float) -> Float {
        0.0012 / rigBucket(rigScale)
    }

    nonisolated static func rigBucket(_ rigScale: Float) -> Float {
        let rig = max(rigScale, 1e-3)
        return pow(1.12, (log(rig) / log(1.12)).rounded())
    }

    /// Which ribbon each body is drawing on, for a test.
    func trailSlot(for id: UUID) -> Int? { ribbonSlots[id] }
    var liveTrailRibbons: Int { ribbons?.liveCount ?? 0 }

    /// How often the trail mesh goes to the renderer: at most this often
    /// while a trail is growing, and this often when only the fades and the
    /// heads move. Every frame was 1.3 MB ninety times a second — sixteen
    /// slots of 512 samples, and a `LowLevelMesh` write ships the whole
    /// buffer — and the simulator's main thread spent nearly half of every
    /// frame waiting on the renderer and none of it idle.
    nonisolated static let trailGrowInterval = 1.0 / 30
    nonisolated static let trailDriftInterval = 1.0 / 10

    private func syncTrails(_ model: OrbitalMechanicsModel) {
        guard let ribbons else { return }
        let wall = CACurrentMediaTime()
        let now = model.simulatedSeconds
        let radius = Self.trailRadius(rigScale: rigScale)
        let scrubbed = ribbonScrubNonce != model.scrubNonce
        ribbonScrubNonce = model.scrubNonce

        var drawn: [(slot: Int, body: OrbitalMechanicsModel.OrbitingBody, head: SIMD3<Float>,
                     reshaped: Bool)] = []
        var live = Set<UUID>()
        var growing = scrubbed
        var moving = false
        for orbiting in model.bodies {
            let slot: Int
            if let existing = ribbonSlots[orbiting.id] {
                slot = existing
            } else if let free = (0..<ribbonCount).first(where: { index in
                !ribbonSlots.values.contains(index)
            }) {
                slot = free
                ribbonSlots[orbiting.id] = free
                ribbonGenerations[free] = nil
                ribbonMaterialKeys[free] = ""
            } else {
                continue
            }
            live.insert(orbiting.id)
            let trail = orbiting.trail
            guard !trail.isEmpty else {
                ribbons.clear(slot: slot)
                committedHeads[slot] = nil
                ribbonGenerations[slot] = trail.generation
                continue
            }

            // The body's own colour; the material changes only when the ramp
            // lands or the slot changes bodies. The leader is the ribbon's
            // head: the ramp's full opacity, or the flat 0.6 before it lands.
            let materialKey = orbiting.body.name + (fadeRamp == nil ? "|flat" : "|faded")
            if ribbonMaterialKeys[slot] != materialKey {
                ribbonMaterialKeys[slot] = materialKey
                let colour = DesignTokens.Palette.celestialUI(orbiting.body.name)
                ribbons.setMaterial(fadeRamp.map { Materials.fadedLine(colour, ramp: $0) }
                                    ?? Materials.unlit(colour, opacity: 0.6), slot: slot)
                leaders[slot].model?.materials = [fadeRamp == nil
                    ? Materials.unlit(colour, opacity: 0.6) : Materials.unlit(colour)]
            }

            let head = SIMD3<Float>(orbiting.body.position) * scale
            let reshaped = ribbonGenerations[slot] != trail.generation
                || ribbonRadii[slot] != radius || scrubbed
            growing = growing || reshaped
            moving = moving || ribbonHeads[slot] != head
            ribbonHeads[slot] = head
            drawn.append((slot, orbiting, head, reshaped))
        }
        // A body that merged or was deleted takes its ribbon with it.
        for (id, slot) in ribbonSlots where !live.contains(id) {
            ribbons.clear(slot: slot)
            committedHeads[slot] = nil
            ribbonSlots.removeValue(forKey: id)
            ribbonGenerations[slot] = nil
            ribbonMaterialKeys[slot] = ""
        }

        // A trail still led by its leader settles onto its body once paused.
        let trailing = drawn.contains { committedHeads[$0.slot] != $0.head }
        let interval = growing ? Self.trailGrowInterval : Self.trailDriftInterval
        let due = scrubbed
            || ((growing || moving || trailing || !model.isPaused)
                && wall - lastTrailCommit >= interval)
        if due {
            lastTrailCommit = wall
            for entry in drawn {
                let trail = entry.body.trail
                let window = model.trailWindow(for: entry.body)
                // Samples, then the body itself as the head.
                let points = trail.samples.map { SIMD3<Float>($0.position) * scale } + [entry.head]
                let ages = trail.samples.map { Float(trail.age($0, now: now, window: window)) } + [1]
                if entry.reshaped {
                    ribbons.update(slot: entry.slot, points: points, ages: ages, radius: radius)
                } else {
                    ribbons.updateHead(slot: entry.slot, points: points, ages: ages, radius: radius)
                }
                ribbonGenerations[entry.slot] = trail.generation
                ribbonRadii[entry.slot] = radius
                committedHeads[entry.slot] = entry.head
            }
        }
        // Clears go at once; the rest only when due.
        ribbons.commit()

        // Every frame, by transform alone: the leader carries each trail from
        // the head it was last written with to where the body is now, so the
        // ribbon ends on the planet at any clock between commits.
        var leading = Set<Int>()
        for entry in drawn {
            guard let from = committedHeads[entry.slot] else { continue }
            let span = entry.head - from
            let length = simd_length(span)
            guard length > 0.0005 else { continue }
            let leader = leaders[entry.slot]
            leader.position = from + span / 2
            leader.orientation = VectorFieldArrows.rotationFromYAxis(to: span / length)
            leader.scale = SIMD3(radius, length, radius)
            leading.insert(entry.slot)
        }
        for slot in leaders.indices {
            leaders[slot].isEnabled = leading.contains(slot)
        }
    }

    // MARK: Held-body prediction (n-body integration on the worker)

    private nonisolated struct PredictionJob: Sendable {
        var inputs: OrbitalMechanicsModel.PredictionInputs
        var scale: Float
    }

    /// The core tube and the near-black casing swept fatter around it.
    private nonisolated struct PredictionBuffers: Sendable {
        var core = TubeBuffers()
        var casing = TubeBuffers()
    }

    private nonisolated static func computePrediction(_ job: PredictionJob) -> PredictionBuffers {
        let path = NBody.predictedPath(
            bodies: job.inputs.bodies, of: job.inputs.index,
            dt: job.inputs.dt, steps: job.inputs.steps,
            pointStride: job.inputs.pointStride,
            gravitationalConstant: job.inputs.gravitationalConstant,
            softening: job.inputs.softening
        )
        let points = path.map { SIMD3<Float>($0) * job.scale }
        guard points.count >= 2 else { return PredictionBuffers() }
        return PredictionBuffers(
            core: TubeMesh.buffers(lines: [points], radius: Self.predictionRadius),
            casing: TubeMesh.buffers(
                lines: [points],
                radius: Materials.casingRadius(forCore: Self.predictionRadius)))
    }

    private func applyPrediction(_ buffers: PredictionBuffers) {
        guard predictionActive else { return }
        // Rewritten in place (`LiveTube`) while the body is held.
        LiveTube.apply(buffers.core, to: predictionEntity, material: predictionMaterial)
        LiveTube.apply(buffers.core.isEmpty ? TubeBuffers() : buffers.casing,
                       to: predictionCasingEntity, material: predictionCasingMaterial)
    }

    private func syncPrediction(_ model: OrbitalMechanicsModel) {
        guard let inputs = model.heldPredictionInputs() else {
            if predictionActive {
                predictionActive = false
                predictionEntity.model = nil
                // The casing goes with it, or a released body leaves a black thread
                // hanging in the room.
                predictionCasingEntity.model = nil
            }
            return
        }
        predictionActive = true
        // Submit freely: the pipeline coalesces, so the preview refreshes
        // at whatever rate the worker can integrate — never blocking a
        // frame, always tracking the newest hand state.
        predictionPipeline?.submit(PredictionJob(inputs: inputs, scale: scale))
    }

    // MARK: Vectors (lengths are log-scaled)

    private func syncVectors(_ model: OrbitalMechanicsModel) {
        guard let selected = model.selectedBody,
              let readout = model.readout(for: selected) else {
            Fade.tick(velocityArrow.container, visible: false)
            Fade.tick(forceArrow.container, visible: false)
            return
        }
        let origin = SIMD3<Float>(selected.body.position) * scale
        let primary = model.primaryBody

        let velocityDirection = selected.body.velocity - (primary?.body.velocity ?? .zero)
        update(arrow: velocityArrow,
               visible: model.showVelocityVector,
               origin: origin,
               direction: velocityDirection,
               length: 0.04 + 0.05 * log10(1 + readout.speedKmPerS))

        // The NET pull, from the integrator's own law: near a heavy neighbour
        // it visibly leaves the line to the star, which is the perturbation.
        let all = model.bodies.map(\.body)
        let index = model.bodies.firstIndex { $0.id == selected.id } ?? 0
        let acceleration = NBody.accelerations(
            bodies: all, gravitationalConstant: model.effectiveG,
            softening: model.softeningRadii)[index]
        // The net force is m·a along a: one arrow says both (an acceleration
        // arrow drawn beside it was the same line at another length).
        let magnitude = simd_length(acceleration)
        update(arrow: forceArrow,
               visible: model.showForceVector,
               origin: origin,
               direction: acceleration,
               length: 0.03 + 0.03 * log10(1 + magnitude * selected.body.mass / 1e20))
    }

    private func update(
        arrow: Arrow, visible: Bool,
        origin: SIMD3<Float>, direction: SIMD3<Double>, length: Double
    ) {
        let magnitude = simd_length(direction)
        guard visible, magnitude > 1e-12, length.isFinite else {
            Fade.tick(arrow.container, visible: false)
            return
        }
        let l = Float(min(max(length, 0.02), 0.3))
        Fade.tick(arrow.container, visible: true)
        arrow.container.position = origin
        arrow.container.orientation = VectorFieldArrows.rotationFromYAxis(
            to: SIMD3<Float>(direction / magnitude))
        arrow.shaft.scale = [1, l / 0.1, 1]
        arrow.shaft.position = [0, l / 2, 0]
        arrow.head.position = [0, l + 0.014, 0]
    }

    // MARK: Merge flash

    /// When the flash goes out, on the wall clock: a frame count was 0.3 s
    /// only at 90 Hz.
    private var flashOffAt: Double?

    private func syncMergeFlash(_ model: OrbitalMechanicsModel) {
        let now = CACurrentMediaTime()
        if let off = flashOffAt, now >= off {
            flashEntity.isEnabled = false
            flashOffAt = nil
        }
        guard model.mergeNonce != lastMergeNonce else { return }
        lastMergeNonce = model.mergeNonce
        flashEntity.position = SIMD3<Float>(model.lastMergePosition) * scale
        flashEntity.isEnabled = true
        if Motion.isReduced {
            // Under Reduce Motion the flash lights at full size and goes out;
            // nothing swells.
            flashEntity.scale = SIMD3(repeating: 3.0)
        } else {
            flashEntity.scale = SIMD3(repeating: 0.4)
            flashEntity.move(
                to: Transform(scale: SIMD3(repeating: 3.0),
                              translation: flashEntity.position),
                relativeTo: systemRoot,
                duration: 0.3,
                timingFunction: .easeOut
            )
        }
        // Off after the 0.3 s swell: a deadline, not a task per merge.
        flashOffAt = now + 0.3
    }
}
