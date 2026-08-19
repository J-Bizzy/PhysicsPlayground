//
//  GravityLabRenderer.swift
//  Renders the solar system diorama: Sun light, pooled planets, trails, prediction, arrows.
//
//  Frame-rate contract: pools built once; per-frame work is transform writes. Every tube is
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
final class GravityLabRenderer {
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    /// Called from the SpaceView's `onDisappear`: subscriptions and pipeline jobs
    /// outlive this object and must be cancelled explicitly.
    func teardown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        trailPipeline?.cancel()
        predictionPipeline?.cancel()
        gridPipeline?.cancel()
        orbitRing.teardown()
    }

    /// Set by the space view's router while the hand owns a body.
    var manipulatingBodyID: UUID?
    /// The body already acknowledged with a pickup pulse — one flash per grab.
    private var pulsedGrabID: UUID?
    /// Where the release tick plays from when the grab ends.
    private weak var pulsedGrabEntity: Entity?

    /// Where the system center sits in the room.
    static let systemPosition = SIMD3<Float>(0, 1.25, -1.2)

    /// Parent for the selected body's floating data panel; moved each render.
    let selectedAnchor = Entity()

    /// The scaled, placed root the bodies live under — blooms and wells convert through it.
    let systemRoot = Entity()
    /// Pausing materialises velocity/net-force arrows on every body.
    private let frozenVectors = FrozenVectors(budget: GravityLabModel.bodyBudget * 2)
    /// The tapped body's callout — name, speed, distance — beside its open ring.
    private var lookCallout: Callout?
    private var calloutReveal: Float = 0
    /// Gates on per-frame work; NaN keys force the first write.
    private var appliedCalloutReveal: Float = -1
    private var lookCalloutKey: (String, Double, Double) = ("", .nan, .nan)

    // MARK: Predict-then-run — the ghost, its countdown, the verdict
    private let ghostEntity: ModelEntity = {
        var material = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        material.blending = .transparent(opacity: 0.32)
        let ghost = ModelEntity(mesh: .generateSphere(radius: 0.035),
                                materials: [material])
        ghost.name = "prediction-ghost"
        ghost.components.set(InputTargetComponent())
        ghost.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.055)]))
        ghost.components.set(HoverEffectComponent())
        ghost.isEnabled = false
        return ghost
    }()
    /// Aimed by dragging; its one hands-free verb is a step along its own radius.
    var onGhostAdjust: ((Double) -> Void)?

    /// The SpaceView's tap router. BEHIND A BOX: the body pool is built in `init` before
    /// `self` exists, so closures capture this box and `onObjectTap` writes through it.
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
    private var lastVerdict: GravityLabModel.PredictionVerdict?

    /// The ghost while the clock runs; the guess-to-truth line when it stops.
    /// (Distinct from syncPrediction, the held-body trajectory preview.)
    private func syncPredictionGhost(_ model: GravityLabModel) {
        let toDisplay = Float(model.simToDisplay)
        if let prediction = model.prediction {
            if ghostEntity.parent == nil { systemRoot.addChild(ghostEntity) }
            ghostEntity.isEnabled = true
            ghostEntity.position = SIMD3<Float>(prediction.position) * toDisplay
            if ghostCallout == nil {
                let callout = Callout(color: UIColor(white: 0.95, alpha: 1),
                                      textSize: 0.02, offset: SIMD3(0, 0.08, 0))
                callout.setAccessibilityName("Prediction")
                systemRoot.addChild(callout.root)
                ghostCallout = callout
            }
            ghostCallout?.isEnabled = true
            ghostCallout?.anchor(at: ghostEntity.position)
            let daysLeft = max(prediction.resolvesAt - model.simulatedDays, 0)
            ghostCallout?.setText("your guess · "
                                  + PhysicsFormat.measurement(daysLeft, "d", decimals: 0))
        } else {
            ghostEntity.isEnabled = false
            ghostCallout?.isEnabled = false
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
                    var material = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
                    material.blending = .transparent(opacity: 0.7)
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
            verdictLine.isEnabled = visible
            verdictCallout?.isEnabled = visible
        } else {
            verdictLine.isEnabled = false
            verdictCallout?.isEnabled = false
        }
    }

    // MARK: Kepler sweep — two gold sectors and their areas
    private let sweepCurrentEntity = ModelEntity()
    private let sweepHeldEntity = ModelEntity()
    private var sweepCurrentLabel: Callout?
    private var sweepHeldLabel: Callout?
    private static let sweepGold = UIColor(red: 1.0, green: 0.80, blue: 0.30, alpha: 1)
    /// Pure VIEW transform between scene root and system: the two-hand rig drives this and
    /// nothing else, so the simulation keeps running in true SI units while apparent size changes.
    let viewRoot = Entity()
    /// Refreshed per render.
    private var scale: Float = 1

    private let bodyPool: EntityPool<ModelEntity>
    private var bodyMaterialKeys: [String]
    /// Which body each pooled slot is named for. The entity `.name` must BE the uuidString
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

    private let trailPool: EntityPool<Void>
    private var trailEntities: [ModelEntity] = []
    private var trailBuiltCounts: [Int]
    /// The `simToDisplay` the built trail meshes were baked at.
    private var trailBuiltScale: Float = 1
    private var trailMaterialCache: [String: UnlitMaterial] = [:]
    private var activeTrailSlots = 0
    private var trailPipeline: GeometryPipeline<TrailJob, TrailResult>?
    private var predictionPipeline: GeometryPipeline<PredictionJob, PredictionBuffers>?
    private var predictionActive = false
    private var gridPipeline: GeometryPipeline<GridJob, TubeBuffers>?
    private let gridMaterial: UnlitMaterial

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
    private static let predictionRadius: Float = 0.002
    private let flashEntity: ModelEntity
    private var platform: ModelEntity!

    // Field particles (display-space positions, relative to systemRoot).
    private static let particleBudget = 450
    private static let particleLife = 7.0
    private let particlePool: EntityPool<Void>
    private var particlePositions: [SIMD3<Float>] = []
    private var particleAges: [Double] = []
    private var particlesVisible = false

    // Spacetime grid constants; plain enum so the worker reads them without actor hops.
    private nonisolated enum GridSpec {
        static let floorHeight: Float = -0.42
        /// Out past Jupiter's 2.6 m ring, so the biggest wells have floor under them.
        static let extent: Float = 2.9
        static let lineCount = 17
        static let samples = 33
        /// Above this view scale the grid is off — invisible under the floorboards,
        /// and it is the module's second most expensive rebuild.
        static let maximumViewScale: Float = 2.5
    }
    private let gridEntity = ModelEntity()

    private struct Arrow {
        let container: Entity
        let shaft: ModelEntity
        let head: ModelEntity
    }
    private var velocityArrow: Arrow!
    private var accelerationArrow: Arrow!
    private var forceArrow: Arrow!

    private var frameCounter = 0
    private var lastMergeNonce = 0

    init() {
        // FIRST, and as a local — see `TapRouter`.
        let router = TapRouter()
        tapRouter = router

        var grid = UnlitMaterial(color: .white)
        grid.blending = .transparent(opacity: 0.3)
        gridMaterial = grid

        systemRoot.position = Self.systemPosition
        viewRoot.addChild(systemRoot)
        root.addChild(viewRoot)

        // Floating platform — hidden while the spacetime grid takes over as the floor.
        var platformMaterial = UnlitMaterial(color: .black)
        platformMaterial.blending = .transparent(opacity: 0.35)
        platform = ModelEntity(
            mesh: .generateCylinder(height: 0.006, radius: 0.9),
            materials: [platformMaterial]
        )
        platform.position = [0, GridSpec.floorHeight, 0]
        systemRoot.addChild(platform)

        // The spacetime grid (rubber-sheet picture), rebuilt as bodies move.
        systemRoot.addChild(gridEntity)

        // Field particles: a fixed pool of faint dots drifting along the local field.
        var particleMaterial = UnlitMaterial(color: .white)
        particleMaterial.blending = .transparent(opacity: 0.32)
        let particleMesh = MeshResource.generateSphere(radius: 0.0028)
        particlePool = EntityPool(budget: Self.particleBudget) { container in
            container.addChild(ModelEntity(mesh: particleMesh, materials: [particleMaterial]))
        }
        // Born at 1x; the shell follows the rig from the first tick on.
        particlePositions = (0..<Self.particleBudget).map { _ in
            Self.randomParticleHome(spread: 1)
        }
        particleAges = (0..<Self.particleBudget).map { _ in Double.random(in: 0..<Self.particleLife) }
        systemRoot.addChild(particlePool.root)

        // Bodies.
        let bodyMesh = MeshResource.generateSphere(radius: Self.baseBodyRadius)
        bodyPool = EntityPool(budget: GravityLabModel.bodyBudget) { container in
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
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = "Celestial body. Grab to move it; throw it to set a new orbit."
            sphere.components.set(accessibility)
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

        var glowMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.82, blue: 0.5, alpha: 1))
        glowMaterial.blending = .transparent(opacity: 0.16)
        sunGlow = ModelEntity(mesh: .generateSphere(radius: Float(Self.glowBaseRadius)),
                              materials: [glowMaterial])
        systemRoot.addChild(sunGlow)

        audioEmitter.components.set(SpatialAudioComponent())
        systemRoot.addChild(audioEmitter)
        CelestialTextures.warmUp()

        // Trails: one tube entity per body slot.
        trailPool = EntityPool(budget: GravityLabModel.bodyBudget) { _ in }
        for slot in trailPool.slots {
            let tube = ModelEntity()
            slot.entity.addChild(tube)
            slot.entity.isEnabled = true
            trailEntities.append(tube)
        }
        trailBuiltCounts = Array(repeating: -1, count: trailPool.budget)
        systemRoot.addChild(trailPool.root)

        // Held-body orbit prediction: two passes from one recipe so the casing and core
        // opacities stay the house numbers.
        let (predictionCasing, predictionCore) = Materials.contrastLine(
            DesignTokens.Palette.predictedArcUI, coreOpacity: 0.55)
        self.predictionMaterial = predictionCore
        self.predictionCasingMaterial = predictionCasing
        // Casing FIRST, so the core draws over it.
        systemRoot.addChild(predictionCasingEntity)
        systemRoot.addChild(predictionEntity)

        // Merge flash.
        var flashMaterial = UnlitMaterial(color: .white)
        flashMaterial.blending = .transparent(opacity: 0.7)
        flashEntity = ModelEntity(mesh: .generateSphere(radius: 0.03), materials: [flashMaterial])
        flashEntity.isEnabled = false
        systemRoot.addChild(flashEntity)

        // Vector arrows on the selected body.
        velocityArrow = Self.makeArrow(color: DesignTokens.Palette.velocityVectorUI)
        accelerationArrow = Self.makeArrow(color: DesignTokens.Palette.accelerationVectorUI)
        forceArrow = Self.makeArrow(color: DesignTokens.Palette.forceVectorUI)
        for arrow in [velocityArrow!, accelerationArrow!, forceArrow!] {
            systemRoot.addChild(arrow.container)
        }

        selectedAnchor.components.set(BillboardComponent())
        systemRoot.addChild(selectedAnchor)

        // Lagrange point markers; positions written every render.
        let markerMesh = MeshResource.generateSphere(radius: 0.009)
        var markerMaterial = UnlitMaterial(color: DesignTokens.Palette.targetUI)
        markerMaterial.blending = .transparent(opacity: 0.85)
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
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = "Lagrange point \(name)"
            marker.components.set(accessibility)
            lagrangeMarkers.append(marker)
            systemRoot.addChild(marker)
        }

        systemRoot.addChild(orbitRing.root)
        scaleReadout.isEnabled = false
        root.addChild(scaleReadout)

        trailPipeline = GeometryPipeline(
            compute: { Self.computeTrails($0) },
            apply: { [weak self] in self?.applyTrails($0) }
        )
        predictionPipeline = GeometryPipeline(
            compute: { Self.computePrediction($0) },
            apply: { [weak self] in self?.applyPrediction($0) }
        )
        gridPipeline = GeometryPipeline(
            compute: { Self.computeGrid($0) },
            apply: { [weak self] in self?.applyGrid($0) }
        )

        // LAST: `self` is unavailable until every stored property is set, so this is
        // the first point the ghost's action can be attached.
        SpatialActions.attach(
            to: ghostEntity, label: "Predicted path",
            adjust: { [weak self] steps in self?.onGhostAdjust?(steps) })
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

    /// Everything READ rather than simulated holds its size: counter-scaling by 1/rig cancels
    /// the rig exactly. A child positioned on the compensated entity follows its planet; one
    /// positioned inside it stays put in the room — both wanted, both fall out of where position is written.
    private func applyRigCompensation() {
        let compensation = SIMD3<Float>(repeating: 1 / max(rigScale, 0.001))
        for label in bodyLabels { label.scale = compensation }
        for callout in [lookCallout, ghostCallout, verdictCallout,
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

    /// Shows "3.4x" beside the clock bank, or nothing at 1x.
    func showScaleReadout(_ label: String?, anchor: SIMD3<Float>) {
        guard let label else {
            scaleReadout.isEnabled = false
            return
        }
        scaleReadout.isEnabled = true
        scaleReadout.position = anchor
        if scaleReadoutText != label {
            scaleReadoutText = label
            scaleReadout.children.forEach { $0.removeFromParent() }
            let plate = HubScene.namePlate(
                label, accent: UIColor(DesignTokens.Palette.gravityAccent),
                size: PlateStyle.exhibitLabelSize)
            plate.components.set(BillboardComponent())
            scaleReadout.addChild(plate)
        }
    }

    /// The paragraph explaining a Lagrange capture. It follows the body: L1–L3 saddles slide off, L4/L5 hold — the callout tracks whichever, so the text's prediction plays out in view.
    private func syncLagrangeCapture(_ model: GravityLabModel) {
        guard let name = model.capturedPointName,
              let text = GravityLabModel.lagrangeExplanations[name],
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
    private func calloutAnchor(for body: GravityLabModel.OrbitingBody,
                               in model: GravityLabModel) -> SIMD3<Float> {
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

    private func syncOrbitRing(_ model: GravityLabModel) {
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
            mesh: .generateCylinder(height: 0.1, radius: 0.0035), materials: [shaftMaterial])
        let head = ModelEntity(
            mesh: .generateCone(height: 0.03, radius: 0.011), materials: [headMaterial])
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
    private static func frozenSamples(model: GravityLabModel) -> [FrozenVectors.Sample] {
        let bodies = model.bodies.map(\.body)
        guard bodies.count > 1 else { return [] }
        let toDisplay = Float(model.simToDisplay)
        let g = model.effectiveG

        var forces: [SIMD3<Double>] = Array(repeating: .zero, count: bodies.count)
        for i in bodies.indices {
            for j in bodies.indices where j != i {
                let offset = bodies[j].position - bodies[i].position
                let distance = max(simd_length(offset), 1e6)
                forces[i] += offset / distance
                    * (g * bodies[i].mass * bodies[j].mass / (distance * distance))
            }
        }
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

    /// Kepler's second law, painted: the sector the radius vector is
    /// sweeping NOW in bright gold, the last completed window held in
    /// dim gold beside it, each engraved with its area. Near perihelion
    /// the sector is short and fat; near aphelion long and thin; the
    /// numbers match. Nothing here is drawn from theory — both sectors
    /// come from the integrated samples, and PhysicsCore's tests hold
    /// their equality to the law.
    private func syncKeplerSweep(_ model: GravityLabModel) {
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
            guard arc.count >= 2,
                  let mesh = Self.sectorMesh(
                    apex: apex,
                    arc: arc.map { apex + SIMD3<Float>($0) * toDisplay }) else {
                entity.isEnabled = false
                label?.isEnabled = false
                return
            }
            // The MESH genuinely changes — the sector is a different
            // shape every time it is redrawn — but the MATERIAL never
            // did: two fixed opacities, rebuilt from scratch on every
            // call. That is the allocation the 2026-07-30 pass swept out
            // of the voltage skyline and the induction filament, missed
            // here because this one only runs at `frameCounter % 12`.
            // Banked as two constants now.
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

    /// A triangle fan from the apex through the arc, both windings, so
    /// the sector reads from either side of the orbital plane without
    /// leaning on any face-culling API.
    /// The sweep's two materials, built once. The accruing sector and
    /// the held one differ only in opacity, and neither ever changes.
    private static let sweepCurrentMaterial = sweepMaterial(opacity: 0.30)
    private static let sweepHeldMaterial = sweepMaterial(opacity: 0.14)

    private static func sweepMaterial(opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: sweepGold)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
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

    private func tickCallout(_ model: GravityLabModel, focusID: UUID?) {
        let toDisplay = Float(model.simToDisplay)
        let orbiting = focusID.flatMap { id in
            model.bodies.first { $0.id == id }
        }
        let target: Float = orbiting == nil ? 0 : 1
        calloutReveal += (target - calloutReveal) * 0.12
        guard let orbiting, calloutReveal > 0.02 else {
            lookCallout?.isEnabled = false
            return
        }
        if lookCallout == nil {
            let callout = Callout(color: UIColor(white: 0.95, alpha: 1),
                                  textSize: 0.024, offset: SIMD3(0, 0.12, 0))
            callout.setAccessibilityName("Selected body")
            systemRoot.addChild(callout.root)
            lookCallout = callout
        }
        lookCallout?.isEnabled = true
        // Opacity written only while the reveal is actually easing;
        // the anchor is a transform and stays per-frame.
        if abs(calloutReveal - appliedCalloutReveal) > 0.0005 {
            appliedCalloutReveal = calloutReveal
            lookCallout?.root.components.set(
                OpacityComponent(opacity: calloutReveal))
        }
        lookCallout?.anchor(at: SIMD3<Float>(orbiting.body.position) * toDisplay)
        // Formatted only when a DISPLAYED digit moves — `Callout`
        // dedupes the mesh, but the string was built every frame for a
        // reading that changes at one decimal.
        if let readout = model.readout(for: orbiting) {
            let key = (orbiting.body.name,
                       (readout.speedKmPerS * 10).rounded(),
                       (readout.distanceAU * 100).rounded())
            if key != lookCalloutKey {
                lookCalloutKey = key
                lookCallout?.setText(String(
                    format: "%@\n%.1f km/s · %.2f AU",
                    key.0, readout.speedKmPerS, readout.distanceAU))
            }
        } else if lookCalloutKey != (orbiting.body.name, -1, -1) {
            // The primary has no orbit to report; it reports itself.
            lookCalloutKey = (orbiting.body.name, -1, -1)
            lookCallout?.setText(orbiting.body.name)
        }
    }

    private func tickOrbitalChord(_ model: GravityLabModel) {
        guard model.playOrbitalChord else {
            chordVoices.values.forEach { $0.mute() }
            chordNotes.removeAll()
            return
        }

        // `model.readout(for:)` solves the two-body elements AND sums the
        // potential energy over every other body — so calling it for each
        // body was quadratic work, every frame, to produce a pitch that
        // is audibly constant over that span. Re-derived a few times a
        // second, tracked continuously in position and smoothed in pitch,
        // it sounds identical.
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
            // Sounds from where the body IS, so the chord moves around
            // the room the way the planets do. Every frame — this part
            // is a vector assignment, and it is what makes the chord
            // feel attached to the objects.
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

    func tick(_ model: GravityLabModel, calloutBodyID: UUID? = nil) {
        frameCounter &+= 1
        tickOrbitalChord(model)
        tickCallout(model, focusID: calloutBodyID)
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
        drainTrailUploads()
        syncLagrangeMarkers(model)
        syncSpacetimeGrid(model)
    }

    // MARK: Field particles (ticked every frame by the space view, so the
    // flow keeps moving even while the simulation itself is paused)

    func tickFieldParticles(dt: Double, model: GravityLabModel) {
        // Pause freezes EVERYTHING in time — spins and field flow included.
        guard !model.isPaused else { return }

        // Every body turns slowly on its axis — pure presentation, but it
        // makes the textures live.
        for (index, slot) in bodyPool.slots.enumerated()
        where index < model.bodies.count {
            let rate: Float = model.bodies[index].body.name.hasPrefix("Sun") ? 0.06 : 0.22
            slot.payload.orientation = simd_quatf(angle: rate * Float(dt), axis: [0, 1, 0])
                * slot.payload.orientation
        }

        guard model.showFieldParticles else {
            if particlesVisible {
                particlePool.hideAll()
                particlesVisible = false
            }
            return
        }
        particlesVisible = true

        let bodies = model.bodies
        guard !bodies.isEmpty else { return }
        let G = model.effectiveG
        let toSim = model.displayToSim
        // Field strength at the scene's natural distance from the primary —
        // the yardstick that maps acceleration to a visible drift speed.
        let primaryMass = model.primaryBody?.body.mass ?? 1
        let referenceAcceleration = G * primaryMass
            / (model.characteristicLength * model.characteristicLength)

        for index in 0..<Self.particleBudget {
            var position = particlePositions[index]
            particleAges[index] += dt

            // True local field: a = Σ G·m·r̂/r², same math the planets feel.
            let simPoint = SIMD3<Double>(position) * toSim
            var acceleration = SIMD3<Double>.zero
            var nearBody = false
            for orbiting in bodies {
                let offset = orbiting.body.position - simPoint
                let distanceSquared = simd_length_squared(offset)
                acceleration += (G * orbiting.body.mass
                    / (distanceSquared * distanceSquared.squareRoot())) * offset
                let displayDistance = distanceSquared.squareRoot() / toSim
                if displayDistance < orbiting.displayRadius * 1.7 { nearBody = true }
            }
            let magnitude = simd_length(acceleration)

            if magnitude > 0 {
                // Drift along the field; speed grows sub-linearly with
                // strength so the far field still visibly creeps.
                let speed = 0.05 + 0.22 * min(1, pow(magnitude / referenceAcceleration, 0.35))
                position += SIMD3<Float>(acceleration / magnitude) * Float(speed * dt)
            }

            // Absorbed, expired, or wandered off: respawn somewhere fresh.
            if nearBody || particleAges[index] > Self.particleLife
                || simd_length(position) > 1.6 * particleSpread {
                position = Self.randomParticleHome(spread: particleSpread)
                particleAges[index] = 0
            }
            particlePositions[index] = position

            // Fade in at birth and out near death by scaling.
            let age = particleAges[index]
            let fade = max(0.02, min(age / 0.6, (Self.particleLife - age) / 0.8, 1))
            let slot = particlePool.slots[index]
            slot.entity.isEnabled = true
            slot.entity.position = position
            slot.entity.scale = SIMD3(repeating: Float(fade))
        }
    }

    private static func randomParticleHome(spread: Float) -> SIMD3<Float> {
        // A point in a spherical shell around the system, biased outward
        // so particles enter from the quiet far field.
        var direction = SIMD3<Float>(
            Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1))
        let length = simd_length(direction)
        direction = length > 1e-5 ? direction / length : SIMD3(0, 1, 0)
        return direction * Float.random(in: 0.45...1.5) * spread
    }

    /// How far the particle shell reaches, in DISPLAY metres, as a
    /// multiple of its 1x size.
    ///
    /// Inversely proportional to the view scale, which keeps the shell
    /// roughly the same size IN THE ROOM whatever the rig is doing. Four
    /// hundred and fifty particles are a field when they fill the volume
    /// around your head and a scattering of dust when they are spread
    /// over fifteen metres — so rather than growing the budget, the
    /// volume follows the viewer. At 9x they populate the space you are
    /// standing in; at 0.4x they fill the tabletop orrery you are looking
    /// down at.
    private var particleSpread: Float {
        min(max(1 / max(rigScale, 0.001), 0.3), 2.6)
    }

    // MARK: Spacetime grid (the rubber-sheet picture — conceptual only)

    private nonisolated struct GridWell: Sendable {
        var center: SIMD2<Float>
        var weight: Float
    }

    private nonisolated struct GridJob: Sendable {
        var wells: [GridWell]
    }

    private nonisolated static func computeGrid(_ job: GridJob) -> TubeBuffers {
        func height(_ x: Float, _ z: Float) -> Float {
            var dip: Float = 0
            for well in job.wells {
                let d = simd_length(SIMD2(x, z) - well.center)
                dip += well.weight / (1 + (d * d) / (0.22 * 0.22))
            }
            return GridSpec.floorHeight - min(dip * 0.14, 0.2)
        }

        let extent = GridSpec.extent
        var lines: [[SIMD3<Float>]] = []
        lines.reserveCapacity(GridSpec.lineCount * 2)
        for lineIndex in 0..<GridSpec.lineCount {
            let offset = -extent + 2 * extent * Float(lineIndex) / Float(GridSpec.lineCount - 1)
            var alongX: [SIMD3<Float>] = []
            var alongZ: [SIMD3<Float>] = []
            for sample in 0..<GridSpec.samples {
                let t = -extent + 2 * extent * Float(sample) / Float(GridSpec.samples - 1)
                alongX.append(SIMD3(t, height(t, offset), offset))
                alongZ.append(SIMD3(offset, height(offset, t), t))
            }
            lines.append(alongX)
            lines.append(alongZ)
        }
        return TubeMesh.buffers(lines: lines, radius: 0.0011, sides: 3)
    }

    private func applyGrid(_ buffers: TubeBuffers) {
        guard gridEntity.isEnabled, let mesh = TubeMesh.mesh(from: buffers) else { return }
        gridEntity.model = ModelComponent(mesh: mesh, materials: [gridMaterial])
    }

    private func syncSpacetimeGrid(_ model: GravityLabModel) {
        let show = model.showSpacetimeGrid && rigScale <= GridSpec.maximumViewScale
        platform.isEnabled = !show && rigScale <= GridSpec.maximumViewScale
        gridEntity.isEnabled = show
        // Resubmit at a third of the render rate; bodies barely move per
        // frame, and the sheet itself is sampled on the worker.
        guard show, frameCounter % 3 == 0 else { return }

        // Well weight ∝ m^¼ — deliberately compressed so planets still dent
        // the sheet visibly beside the Sun. Conceptual, and labeled so.
        let maxMass = model.bodies.map(\.body.mass).max() ?? 1
        let wells = model.bodies.map { orbiting in
            let display = SIMD3<Float>(orbiting.body.position) * scale
            return GridWell(center: SIMD2(display.x, display.z),
                            weight: Float(pow(orbiting.body.mass / maxMass, 0.25)))
        }
        gridPipeline?.submit(GridJob(wells: wells))
    }

    private func syncLagrangeMarkers(_ model: GravityLabModel) {
        let points = model.lagrangePoints
        for (index, marker) in lagrangeMarkers.enumerated() {
            guard index < points.count else {
                marker.isEnabled = false
                continue
            }
            marker.isEnabled = true
            marker.position = SIMD3<Float>(points[index].position) * scale
        }
    }

    /// Billboarded name tags riding above the bodies — you should never
    /// have to guess which dot is Mars.
    private var bodyLabels: [Entity] = []
    /// ONE MODULE, TWO LABEL TREATMENTS, BOTH ON SCREEN AT ONCE.
    ///
    /// The planet names were 75%-opacity white text with nothing behind
    /// them, while the Lagrange markers in this same file are
    /// `BackedLabel`s wearing the house plate — so turning on the
    /// Lagrange layer put the two styles a few centimetres apart. That
    /// is the "written on different days" tell, inside one renderer.
    ///
    /// Moved onto `BackedLabel` 2026-08-09, which also retires this
    /// file's private `labelMeshCache` in favour of the shared glyph
    /// cache, and centres the run on both axes instead of X only.
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

    private func syncBodies(_ model: GravityLabModel) {
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
            ensureLabel(index)
            // The "material key" IS the body's name, so this gate is
            // already exactly "has this slot changed bodies" — the
            // label belongs inside it, not beside it.
            if bodyMaterialKeys[index] != orbiting.body.name {
                bodyMaterialKeys[index] = orbiting.body.name
                slot.payload.model?.materials = [material(for: orbiting.body.name)]
                bodyLabelPlates[index].setText(orbiting.body.name, color: .white)
            }
            bodyLabels[index].isEnabled = true
            bodyLabels[index].position = SIMD3<Float>(orbiting.body.position) * scale
                + SIMD3(0, Float(orbiting.displayRadius) + 0.028, 0)
            let bodyScale = Float(orbiting.displayRadius) / Self.baseBodyRadius
            slot.entity.scale = SIMD3<Float>(repeating: bodyScale)
            // The target is re-sized WITH the body, so its reach in the
            // room stays constant instead of scaling with the planet —
            // see `Grabbable.sphereTargetRadius`. Change-gated: this
            // allocates a `ShapeResource`, and a body's display radius
            // only moves on a merge or a preset change.
            //
            // ON `slot.payload`, NOT `slot.entity`. The pool is two
            // levels: `slot.entity` is the bare container this scale is
            // written to, and `slot.payload` is the sphere under it that
            // carries the mesh, the `InputTargetComponent` and the
            // body's UUID name — so the sphere is what a pinch hits and
            // what the gesture handlers resolve. Setting this on the
            // container put an inert collider on an entity with no input
            // target, left the real one at its authored 1.15×, and
            // achieved exactly nothing; the criterion could not see it
            // because a fixed 1.15× rides its 1.15 margin at every scale.
            if abs((bodyColliderScales[index] ?? -1) - bodyScale) > 1e-4 {
                bodyColliderScales[index] = bodyScale
                slot.payload.components.set(CollisionComponent(shapes: [
                    .generateSphere(radius: Grabbable.sphereTargetRadius(
                        baseRadius: Self.baseBodyRadius, scale: bodyScale)),
                ]))
            }

            if orbiting.id == manipulatingBodyID {
                // Hand owns the sphere: leave transforms alone.
                if pulsedGrabID != orbiting.id {
                    pulsedGrabID = orbiting.id
                    pulsedGrabEntity = slot.entity
                    PickupPulse.flash(on: slot.entity)
                    SoundPalette.play(.grabTick, on: slot.entity, volume: 0.2)
                }
            } else {
                slot.entity.position = SIMD3<Float>(orbiting.body.position) * scale
                slot.payload.position = .zero
            }
        }
        for index in model.bodies.count..<bodyPool.budget {
            bodyPool.slots[index].entity.isEnabled = false
            if index < bodyLabels.count { bodyLabels[index].isEnabled = false }
        }
        if manipulatingBodyID == nil {
            if pulsedGrabID != nil, let entity = pulsedGrabEntity {
                SoundPalette.play(.releaseTick, on: entity, volume: 0.18)
            }
            pulsedGrabID = nil
            pulsedGrabEntity = nil
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

    /// A world as the WELL shows it, before you have one.
    ///
    /// An Earth-textured sphere at the size a body pulled from the well
    /// actually arrives at, using the same `CelestialTextures` map the
    /// real planets wear — the well makes an Earth-mass world, so it
    /// shows one.
    static func worldPreview() -> Entity {
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.030),
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

    // MARK: Trails (vertex math on the pipeline worker)

    // A JOB CARRIES ONLY THE TRAILS THAT MOVED.
    //
    // It used to carry every body, because the resubmit test was "did
    // ANY trail grow" and the payload was then built for all of them.
    // At sixteen bodies that queued sixteen uploads every fourth frame
    // against a drain of three per frame — six frames of work arriving
    // every four — so the queue never emptied and the main actor did
    // three `MeshResource.generate` calls every frame, permanently. The
    // budget that was meant to spread one burst over five frames had
    // become a floor instead of a ceiling.
    //
    // `slots` says which body each entry belongs to, so a partial job
    // still lands on the right entities. In steady flight one or two
    // trails cross the 8 mm spacing threshold in any given window, so
    // the queue now drains and the renderer goes quiet between them.
    private nonisolated struct TrailJob: Sendable {
        var slots: [Int]
        var names: [String]
        var lines: [[SIMD3<Float>]]
    }

    private nonisolated struct TrailResult: Sendable {
        var slots: [Int]
        var names: [String]
        var buffers: [TubeBuffers]
    }

    private nonisolated static func computeTrails(_ job: TrailJob) -> TrailResult {
        TrailResult(
            slots: job.slots,
            names: job.names,
            buffers: job.lines.map { line in
                line.count >= 2
                    ? TubeMesh.buffers(lines: [line], radius: 0.0012)
                    : TubeBuffers()
            }
        )
    }

    /// Meshes waiting to be handed to the GPU, at most a few per frame.
    private var pendingTrailUploads: [(index: Int, buffers: TubeBuffers, name: String)] = []
    /// How many trail meshes may be uploaded in one frame.
    ///
    /// THE VERTEX MATH WAS ALREADY OFF THE MAIN THREAD; THE UPLOAD WAS
    /// NOT. `TubeMesh.buffers` runs on the pipeline worker, but
    /// `MeshResource.generate` has to happen on the main actor, and this
    /// function used to do every body's in one callback — twelve mesh
    /// uploads inside a single frame, which was the module's largest
    /// hitch. Raising the body budget to sixteen would have made it a
    /// third worse. Three a frame spreads the same work over five frames
    /// at ninety hertz, which is under a tenth of a second: slower than
    /// the physics and far faster than the eye.
    private static let trailUploadsPerFrame = 3

    private func applyTrails(_ result: TrailResult) {
        // APPENDED, not assigned. A partial job means a second job can
        // arrive while the first is still draining, and overwriting the
        // queue would drop trails that were computed but never uploaded
        // — a body whose line then stops growing until the next time it
        // happens to be in a batch. Anything still queued for the same
        // slot is superseded, so the newer buffers win.
        let arriving = Set(result.slots)
        pendingTrailUploads.removeAll { arriving.contains($0.index) }
        for (position, buffers) in result.buffers.enumerated() {
            guard position < result.slots.count, position < result.names.count
            else { continue }
            let index = result.slots[position]
            guard index < trailEntities.count, index < activeTrailSlots
            else { continue }
            pendingTrailUploads.append((index, buffers, result.names[position]))
        }
        drainTrailUploads()
    }

    /// Hands the next few meshes over. Called from `applyTrails` and then
    /// once per tick until the queue is empty.
    private func drainTrailUploads() {
        guard !pendingTrailUploads.isEmpty else { return }
        let batch = pendingTrailUploads.prefix(Self.trailUploadsPerFrame)
        pendingTrailUploads.removeFirst(batch.count)
        for upload in batch {
            // The body may have merged or been deleted between the
            // submission and this frame's slice of the upload.
            guard upload.index < activeTrailSlots else { continue }
            if let mesh = TubeMesh.mesh(from: upload.buffers) {
                trailEntities[upload.index].model = ModelComponent(
                    mesh: mesh, materials: [trailMaterial(for: upload.name)])
            } else {
                trailEntities[upload.index].model = nil
            }
        }
    }

    private func trailMaterial(for name: String) -> UnlitMaterial {
        if let cached = trailMaterialCache[name] { return cached }
        var material = UnlitMaterial(color: DesignTokens.Palette.celestialUI(name))
        material.blending = .transparent(opacity: 0.5)
        trailMaterialCache[name] = material
        return material
    }

    private func syncTrails(_ model: GravityLabModel) {
        activeTrailSlots = min(model.bodies.count, trailPool.budget)
        for index in activeTrailSlots..<trailPool.budget
        where trailBuiltCounts[index] != -1 {
            trailEntities[index].model = nil
            trailBuiltCounts[index] = -1
        }

        // One coalescing job, carrying ONLY the trails that grew —
        // `trailBuiltCounts` already tracked this per body and the old
        // code used it as a single yes/no for the whole system.
        guard frameCounter % 4 == 0 else { return }

        let scale = self.scale
        // TRAIL VERTICES ARE BAKED IN DISPLAY SPACE, so a change of
        // `simToDisplay` invalidates every built line at once — nothing
        // about a body's own trail says its mesh is now the wrong size.
        //
        // This was already wrong before the per-body submit and was
        // hidden by the coarser one: the old code rebuilt ALL trails
        // whenever ANY grew, so a rescale was silently repaired by the
        // next body to cross the spacing threshold. Submitting only
        // what grew would have left the others at the old scale
        // indefinitely — a rescale you can see, one orbit at a time.
        if trailBuiltScale != scale {
            trailBuiltScale = scale
            for index in trailBuiltCounts.indices where trailBuiltCounts[index] != -1 {
                trailBuiltCounts[index] = -1
            }
        }

        var slots: [Int] = []
        var names: [String] = []
        var lines: [[SIMD3<Float>]] = []
        for index in 0..<activeTrailSlots {
            let orbiting = model.bodies[index]
            guard orbiting.trail.count != trailBuiltCounts[index] else { continue }
            slots.append(index)
            names.append(orbiting.body.name)
            lines.append(orbiting.trail.map { SIMD3<Float>($0) * scale })
            trailBuiltCounts[index] = orbiting.trail.count
        }
        guard !slots.isEmpty else { return }
        trailPipeline?.submit(TrailJob(slots: slots, names: names, lines: lines))
    }

    // MARK: Held-body prediction (n-body integration on the worker)

    private nonisolated struct PredictionJob: Sendable {
        var inputs: GravityLabModel.PredictionInputs
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
            gravitationalConstant: job.inputs.gravitationalConstant
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
        if let mesh = TubeMesh.mesh(from: buffers.core) {
            predictionEntity.model = ModelComponent(mesh: mesh, materials: [predictionMaterial])
            predictionCasingEntity.model = TubeMesh.mesh(from: buffers.casing).map {
                ModelComponent(mesh: $0, materials: [predictionCasingMaterial])
            }
        } else {
            predictionEntity.model = nil
            predictionCasingEntity.model = nil
        }
    }

    private func syncPrediction(_ model: GravityLabModel) {
        guard let inputs = model.heldPredictionInputs() else {
            if predictionActive {
                predictionActive = false
                predictionEntity.model = nil
                // The casing goes with it. Left behind, a released body
                // leaves a black thread of its own predicted path
                // hanging in the room with no arc inside it.
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

    // MARK: Vectors (lengths are log-scaled; the legend says so)

    private func syncVectors(_ model: GravityLabModel) {
        guard let selected = model.selectedBody,
              let readout = model.readout(for: selected),
              selected.id != manipulatingBodyID else {
            Fade.tick(velocityArrow.container, visible: false)
            Fade.tick(accelerationArrow.container, visible: false)
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

        let towardPrimary = (primary?.body.position ?? .zero) - selected.body.position
        update(arrow: accelerationArrow,
               visible: model.showAccelerationVector,
               origin: origin,
               direction: towardPrimary,
               length: 0.03 + 0.04 * log10(1 + readout.accelerationMS2 * 1e3))
        update(arrow: forceArrow,
               visible: model.showForceVector,
               origin: origin,
               direction: towardPrimary,
               length: 0.03 + 0.03 * log10(1 + readout.forceNewtons / 1e20))
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

    private func syncMergeFlash(_ model: GravityLabModel) {
        guard model.mergeNonce != lastMergeNonce else { return }
        lastMergeNonce = model.mergeNonce
        flashEntity.position = SIMD3<Float>(model.lastMergePosition) * scale
        flashEntity.scale = SIMD3(repeating: 0.4)
        flashEntity.isEnabled = true
        flashEntity.move(
            to: Transform(scale: SIMD3(repeating: 3.0),
                          translation: flashEntity.position),
            relativeTo: systemRoot,
            duration: 0.3,
            timingFunction: .easeOut
        )
        Task { [weak flashEntity] in
            try? await Task.sleep(for: .milliseconds(320))
            flashEntity?.isEnabled = false
        }
    }
}
