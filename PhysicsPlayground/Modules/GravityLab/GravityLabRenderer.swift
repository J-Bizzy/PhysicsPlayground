//
//  GravityLabRenderer.swift
//  Physics Playground — Gravity Lab module
//
//  Renders the solar system diorama: a glowing Sun that actually lights
//  nearby bodies (PointLight), pooled planets (grabbable, hover-lit by
//  the system), per-body orbit trails, the held-body orbit prediction,
//  velocity/acceleration/force arrows on the selected body, and a soft
//  flash when bodies merge.
//
//  Frame-rate contract: pools built once; per-frame work is transform
//  writes. Every tube — orbit trails, the held-body prediction (a
//  1200-step n-body integration), and the spacetime grid — is computed
//  on a GeometryPipeline worker; the main thread only uploads finished
//  buffers. Materials are created once and cached. Ticked per frame
//  from SceneEvents.Update (observation loops starve during grabs —
//  house rule since the EM module's device findings).
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

    /// Called from the SpaceView's `onDisappear`, and the reason it has
    /// to be called explicitly is that neither of the things it releases
    /// is tied to this object's lifetime.
    ///
    /// An `EventSubscription` outlives the view that made it — cancelled
    /// nowhere, it keeps calling into a renderer for a scene that is no
    /// longer on screen and holds the whole entity graph alive behind
    /// it. And a `GeometryPipeline` job in flight ran to completion and
    /// then uploaded a mesh and enabled an entity in a scene being torn
    /// down (see `GeometryPipeline.cancel`).
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
    /// The body already acknowledged with a pickup pulse — one flash per
    /// grab, not one per frame.
    private var pulsedGrabID: UUID?
    /// Where the release tick plays from when the grab ends.
    private weak var pulsedGrabEntity: Entity?

    /// Where the system center sits in the room.
    static let systemPosition = SIMD3<Float>(0, 1.25, -1.2)

    /// Parent for the selected body's floating data panel (the space view
    /// attaches the SwiftUI attachment here; we move it each render).
    let selectedAnchor = Entity()

    /// The scaled, placed root the bodies live under — blooms and
    /// wells convert through it like every hand does.
    let systemRoot = Entity()
    /// Freeze sculpts: pausing materialises velocity and net-force
    /// arrows on every body, in the app-wide frozen-vector language.
    private let frozenVectors = FrozenVectors(budget: GravityLabModel.bodyBudget * 2)
    /// The tapped body introduces itself — name, speed, distance —
    /// beside its open control ring, and falls quiet when it folds.
    private var lookCallout: Callout?
    private var calloutReveal: Float = 0

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
    /// The ghost is aimed by dragging, so like the apsis beads its one
    /// hands-free verb is a step in or out along its own radius.
    var onGhostAdjust: ((Double) -> Void)?
    private var ghostCallout: Callout?
    private var verdictLine = Entity()
    private var verdictCallout: Callout?
    private var verdictShownWall: Double?
    private var lastVerdict: GravityLabModel.PredictionVerdict?

    /// The ghost while the clock runs; the guess-to-truth line when it
    /// stops. Being wrong is drawn, measured, and then allowed to fade
    /// — the point is the gap, not the grade. (Distinct from
    /// syncPrediction, the held-body trajectory preview.)
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
            ghostCallout?.setText(String(format: "your guess · %.0f d", daysLeft))
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
                verdictCallout?.setText(String(format: verdict.missAU < 0.1
                    ? "off by %.2f AU — called it" : "off by %.2f AU",
                    verdict.missAU))
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
    /// A pure VIEW transform between the scene root and the system: the
    /// two-handed scale/turn rig drives this and nothing else, so the
    /// simulation keeps running in true SI units at its own scale while
    /// the user changes how big it looks. Pinch with both hands and pull
    /// apart to go from a tabletop orrery to a solar system you stand
    /// inside — the one gesture that only exists in a headset, and the
    /// module that most needed it, since at 1 AU = 0.5 m the inner
    /// planets are a disc you could cover with a dinner plate.
    let viewRoot = Entity()
    /// Mode-dependent (AU scale vs. Earth–Moon scale); refreshed per render.
    private var scale: Float = 1

    private let bodyPool: EntityPool<ModelEntity>
    private var bodyMaterialKeys: [String]
    /// The scale each pooled body's touch target was last sized for.
    private var bodyColliderScales: [Int: Float] = [:]
    private var bodyNames: [String]
    private static let baseBodyRadius: Float = 0.05

    private let trailPool: EntityPool<Void>
    private var trailEntities: [ModelEntity] = []
    private var trailBuiltCounts: [Int]
    private var trailMaterialCache: [String: UnlitMaterial] = [:]
    private var activeTrailSlots = 0
    private var trailPipeline: GeometryPipeline<TrailJob, TrailResult>?
    private var predictionPipeline: GeometryPipeline<PredictionJob, TubeBuffers>?
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
    private let flashEntity: ModelEntity
    private var platform: ModelEntity!

    // Field particles (display-space positions, relative to systemRoot).
    private static let particleBudget = 450
    private static let particleLife = 7.0
    private let particlePool: EntityPool<Void>
    private var particlePositions: [SIMD3<Float>] = []
    private var particleAges: [Double] = []
    private var particlesVisible = false

    // Spacetime grid. Constants live in a plain enum so the background
    // grid computation can read them without actor hops.
    private nonisolated enum GridSpec {
        static let floorHeight: Float = -0.42
        /// Out past Jupiter's 2.6 m ring. It was 1.4 m, which stops at
        /// Mars — so the four biggest wells in the scene had no floor
        /// under them at all, and the rubber sheet ended in mid-air
        /// exactly where the interesting orbits begin.
        static let extent: Float = 2.9
        static let lineCount = 17
        static let samples = 33
        /// Above this view scale the grid is switched off. At 3x the
        /// sheet is 1.3 m below your feet and stretches 17 m out; you are
        /// standing INSIDE the inner system by then, and a rubber sheet
        /// under the floorboards is neither visible nor meaningful. It is
        /// also the module's second most expensive rebuild.
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
        var grid = UnlitMaterial(color: .white)
        grid.blending = .transparent(opacity: 0.3)
        gridMaterial = grid

        systemRoot.position = Self.systemPosition
        viewRoot.addChild(systemRoot)
        root.addChild(viewRoot)

        // The floating platform under the system — a quiet glass disc.
        // Hidden while the spacetime grid takes over as the floor.
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

        // Field particles: a fixed pool of faint dots that drift along the
        // local gravitational field. Density near masses emerges from the
        // flow itself — strong fields pull the streamlines together.
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
            // 1.5× until 2026-08-07. The factor survives the per-body
            // scale, so it was 1.5× at every size — and an apsis bead
            // drawn in the 1.0–1.5 r annulus around a planet was visible,
            // hover-lit and completely unpinchable.
            Grabbable.configureTouchTarget(sphere, collisionRadius: Self.baseBodyRadius * 1.15)
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = "Celestial body. Grab to move it; throw it to set a new orbit."
            sphere.components.set(accessibility)
            container.addChild(sphere)
            return sphere
        }
        bodyMaterialKeys = Array(repeating: "", count: bodyPool.budget)
        bodyNames = Array(repeating: "", count: bodyPool.budget)
        systemRoot.addChild(bodyPool.root)
        systemRoot.addChild(frozenVectors.root)
        for sector in [sweepCurrentEntity, sweepHeldEntity] {
            sector.isEnabled = false
            systemRoot.addChild(sector)
        }

        // The Sun's light: warm, following the heaviest body — plus a
        // soft corona shell so it reads as incandescent, not painted.
        // 40 m, not 5. Neptune's orbit is a 15 m ring at 1x, so a 5 m
        // attenuation radius meant the Sun lit as far as Saturn and no
        // further: from there out the planets were lit only by the room's
        // own key light, which comes from the wrong direction entirely.
        // The one cue this scene cannot afford to lose is which side of a
        // planet faces the Sun.
        sunLight.components.set(PointLightComponent(
            color: UIColor(red: 1.0, green: 0.9, blue: 0.75, alpha: 1),
            intensity: 12_000,
            attenuationRadius: 40
        ))
        systemRoot.addChild(sunLight)

        var glowMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.82, blue: 0.5, alpha: 1))
        glowMaterial.blending = .transparent(opacity: 0.16)
        sunGlow = ModelEntity(mesh: .generateSphere(radius: 0.105), materials: [glowMaterial])
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

        // Held-body orbit prediction.
        var predictionMaterial = UnlitMaterial(color: DesignTokens.Palette.predictedArcUI)
        predictionMaterial.blending = .transparent(opacity: 0.55)
        self.predictionMaterial = predictionMaterial
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

        // Lagrange point markers: five small diamonds with labels,
        // co-rotating with the Moon (positions written every render).
        let markerMesh = MeshResource.generateSphere(radius: 0.009)
        var markerMaterial = UnlitMaterial(color: DesignTokens.Palette.targetUI)
        markerMaterial.blending = .transparent(opacity: 0.85)
        for name in ["L1", "L2", "L3", "L4", "L5"] {
            let marker = ModelEntity(mesh: markerMesh, materials: [markerMaterial])
            // The house dark plate behind the name (2026-08-06); the
            // pivot lifts to where the run's centre sat when the text
            // was baseline-anchored.
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

        // LAST, because `self` is not available until every stored
        // property is initialised — the ghost is built in a
        // stored-property closure that has no `self` to capture, so this
        // is the first point its action can be attached at all.
        SpatialActions.attach(
            to: ghostEntity, label: "Predicted path",
            adjust: { [weak self] steps in self?.onGhostAdjust?(steps) })
    }

    private var lagrangeMarkers: [ModelEntity] = []
    /// Retains the markers' BackedLabels (the entity graph holds only
    /// their roots).
    private var lagrangeLabels: [BackedLabel] = []

    // MARK: The orbit ring — the selected body's conic, as an object
    //
    // Under `systemRoot`, like the wells and the bloom, and for the same
    // reason: a hand arrives here through `displayPoint(fromWorld:)`, and
    // an anchor parented in one frame while positioned in another lands
    // nowhere near the thing it belongs to.
    private let orbitRing = OrbitRing(
        accent: UIColor(DesignTokens.Palette.gravityAccent))

    /// Which apsis bead an entity is, if any — the renderer owns the
    /// beads, so the renderer answers whether a pinch landed on one.
    /// Mirrors `Well.pull(_:at:)` in shape.
    func apsis(for entity: Entity) -> Apsis? { orbitRing.apsis(for: entity) }

    /// Forwards a VoiceOver step on an apsis bead to whoever owns the
    /// model — see `OrbitRing.onAdjust`.
    var onApsisAdjust: ((Apsis, Double) -> Void)? {
        get { orbitRing.onAdjust }
        set { orbitRing.onAdjust = newValue }
    }

    func beadDisplayPoint(_ apsis: Apsis) -> SIMD3<Double> {
        orbitRing.beadDisplayPoint(apsis)
    }

    /// The viewer, needed for the beads' reach rule. Written by the space
    /// view each frame, already converted into the system's own frame.
    var viewerInSystem: SIMD3<Float>?
    /// The two-hand rig's live scale, so the beads can compensate for it.
    var rigScale: Float = 1

    /// EVERYTHING THAT IS READ RATHER THAN SIMULATED HOLDS ITS SIZE.
    ///
    /// The rig scales `systemRoot`, and it has to: the planets, their
    /// orbits, the trails and the rings are the thing being resized, and
    /// resizing them is the whole gesture. But the LABELS are not part of
    /// the solar system. A 22 mm name plate parented in that frame is
    /// 20 cm tall at 9x and 9 mm at 0.4x — unreadable at both ends, for
    /// opposite reasons — and the spawn well, which is an instrument and
    /// not an object in the sky, ends up a 29 cm ball five metres to your
    /// left at full zoom.
    ///
    /// Counter-scaling by 1/rig cancels the rig exactly. Note what it
    /// does for a child whose POSITION is set on the compensated entity
    /// itself (a name plate follows its planet, because the plate's
    /// position is on the holder and the scale only reaches its
    /// children) versus one set on a child (the well stays put in the
    /// room, because both its offset and its size are inside the
    /// compensated root). Both behaviours are the ones wanted, and they
    /// fall out of where the position is written.
    ///
    /// `Bloom` already does this for itself, by distance rather than by
    /// rig — see its `update`. This is the same rule for everything that
    /// is not a bloom.
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

    /// Instruments parented under `systemRoot` that must keep their size
    /// and their place in the room — the spawn well, chiefly. Registered
    /// by the space view, which owns them.
    private var rigCompensatedInstruments: [Entity] = []

    func compensateForRig(_ entity: Entity) {
        rigCompensatedInstruments.append(entity)
    }

    // MARK: The scale readout
    //
    // The rig is the module's signature gesture and it had no readout at
    // all: nothing anywhere said whether you were at 1x or 6x, so "how
    // big is this now" could only be answered by recognising a planet.
    // Under `root`, so the readout does not resize along with the thing
    // it is reporting on.

    private let scaleReadout = Entity()
    private var scaleReadoutText: String?

    /// Shows "3.4x" beside the clock bank, or nothing at 1x — the
    /// affordance only means something once the view has been changed.
    ///
    /// It took a `viewer:` and discarded it: the plate carries a
    /// `BillboardComponent`, so RealityKit aims it at the camera every
    /// frame and there is nothing for a head position to do here.
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
                size: 0.030)
            plate.components.set(BillboardComponent())
            scaleReadout.addChild(plate)
        }
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
        // IN THE RING'S FRAME, not the system's. `OrbitRing.root` sits on
        // the primary and its beads are placed relative to it, so an
        // absolute centre here is offset from the beads by the primary's
        // own position — wrong by 0.2 AU the moment "Twin suns" moves the
        // primary off the origin, and invisible before that because
        // `reset()` puts the Sun at exactly zero.
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
        // Clean bright shaft (a line), glossy self-lit head (a crafted tip
        // that catches the key light) — a confident vector, not a wire.
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

    /// Room coordinates → display coordinates relative to the system
    /// centre.
    ///
    /// This used to subtract a constant, which was correct only while
    /// the system sat at 1× with no turn. Now that the view root can be
    /// scaled and rotated by the two-handed gesture, the conversion has
    /// to go through the actual transform — otherwise grabbing a planet
    /// in a zoomed-in view would fling it, because the hand's motion
    /// would be read as a much larger motion in simulation space.
    /// `convert` inverts whatever the view rig has done, exactly.
    func displayPoint(fromWorld world: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3<Double>(systemRoot.convert(position: world, from: nil))
    }

    // MARK: The orbital chord — Kepler's third law, heard

    /// One voice per body, pitched by its orbital period.
    ///
    /// Kepler's harmonices mundi, made literal: a period maps to a
    /// frequency, so the solar system is a CHORD. Earth's year is the
    /// reference note; Mercury's 88-day year sings about two octaves
    /// above it, Neptune's 165 years growls at the floor. The point is
    /// what happens when you interfere: throw a planet into a new orbit
    /// and you HEAR its note slide, and hear the chord go out of tune,
    /// while you are still looking at your hands. T² ∝ a³ stops being a
    /// formula and becomes an interval you can recognise.
    private var chordVoices: [UUID: ToneVoice] = [:]
    private var chordEmitters: [UUID: Entity] = [:]

    /// The note each body is currently singing, so the per-frame work is
    /// "keep singing it from over there" rather than "work out what a
    /// year is here". See `tickOrbitalChord`.
    private var chordNotes: [UUID: (pitch: Double, loudness: Double)] = [:]

    /// How often orbital periods are re-derived. An orbit's period is a
    /// property of the whole orbit, not of this instant — it changes when
    /// you add mass or drag a planet, not between one frame and the next.
    private static let chordAnalysisInterval = 12

    /// The frozen readout: every body's velocity, and the net
    /// gravitational pull on it summed over every other body — the same
    /// law the integrator uses, evaluated at the frozen instant. The
    /// pairwise sum is O(n²) and runs ONLY while the arrows are shown.
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
                    // sqrt spreads the slow outer planets off the floor
                    // of the scale instead of vanishing next to Mercury.
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
            label?.setText(String(format: "%.2f AU²", area / (au * au)))
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
        lookCallout?.root.components.set(OpacityComponent(opacity: calloutReveal))
        lookCallout?.anchor(at: SIMD3<Float>(orbiting.body.position) * toDisplay)
        if let readout = model.readout(for: orbiting) {
            lookCallout?.setText(String(
                format: "%@\n%.1f km/s · %.2f AU",
                orbiting.body.name, readout.speedKmPerS, readout.distanceAU))
        } else {
            // The primary has no orbit to report; it reports itself.
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
    private var bodyLabelTexts: [ModelEntity] = []
    private var labelMeshCache: [String: MeshResource] = [:]

    private func labelMesh(for name: String) -> MeshResource {
        if let cached = labelMeshCache[name] { return cached }
        let mesh = MeshResource.generateText(
            name, extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.022, weight: .semibold))
        labelMeshCache[name] = mesh
        return mesh
    }

    private func ensureLabel(_ index: Int) {
        while bodyLabels.count <= index {
            let holder = Entity()
            let pivot = Entity()
            pivot.components.set(BillboardComponent())
            holder.addChild(pivot)
            let text = ModelEntity()
            var material = UnlitMaterial(color: UIColor(white: 1, alpha: 0.75))
            material.blending = .transparent(opacity: 0.75)
            text.model = ModelComponent(mesh: labelMesh(for: " "), materials: [material])
            pivot.addChild(text)
            holder.isEnabled = false
            systemRoot.addChild(holder)
            bodyLabels.append(holder)
            bodyLabelTexts.append(text)
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
            if slot.payload.name != orbiting.id.uuidString {
                slot.payload.name = orbiting.id.uuidString
            }
            ensureLabel(index)
            if bodyMaterialKeys[index] != orbiting.body.name {
                bodyMaterialKeys[index] = orbiting.body.name
                slot.payload.model?.materials = [material(for: orbiting.body.name)]
                let mesh = labelMesh(for: orbiting.body.name)
                bodyLabelTexts[index].model?.mesh = mesh
                let bounds = mesh.bounds
                bodyLabelTexts[index].position = [
                    -(bounds.min.x + bounds.max.x) / 2, 0, 0]
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
                sunGlow.scale = SIMD3(repeating: Float(primary.displayRadius / 0.075))
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

    private nonisolated struct TrailJob: Sendable {
        var names: [String]
        var lines: [[SIMD3<Float>]]
    }

    private nonisolated struct TrailResult: Sendable {
        var names: [String]
        var buffers: [TubeBuffers]
    }

    private nonisolated static func computeTrails(_ job: TrailJob) -> TrailResult {
        TrailResult(
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
        pendingTrailUploads = result.buffers.enumerated().compactMap { index, buffers in
            guard index < trailEntities.count, index < activeTrailSlots,
                  index < result.names.count else { return nil }
            return (index, buffers, result.names[index])
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

        // One coalescing job covers every body; resubmitted at a quarter
        // of the render rate when any trail actually grew.
        guard frameCounter % 4 == 0 else { return }
        var changed = false
        for index in 0..<activeTrailSlots
        where model.bodies[index].trail.count != trailBuiltCounts[index] {
            changed = true
            break
        }
        guard changed else { return }

        let scale = self.scale
        var names: [String] = []
        var lines: [[SIMD3<Float>]] = []
        for index in 0..<activeTrailSlots {
            let orbiting = model.bodies[index]
            names.append(orbiting.body.name)
            lines.append(orbiting.trail.map { SIMD3<Float>($0) * scale })
            trailBuiltCounts[index] = orbiting.trail.count
        }
        trailPipeline?.submit(TrailJob(names: names, lines: lines))
    }

    // MARK: Held-body prediction (n-body integration on the worker)

    private nonisolated struct PredictionJob: Sendable {
        var inputs: GravityLabModel.PredictionInputs
        var scale: Float
    }

    private nonisolated static func computePrediction(_ job: PredictionJob) -> TubeBuffers {
        let path = NBody.predictedPath(
            bodies: job.inputs.bodies, of: job.inputs.index,
            dt: job.inputs.dt, steps: job.inputs.steps,
            pointStride: job.inputs.pointStride,
            gravitationalConstant: job.inputs.gravitationalConstant
        )
        let points = path.map { SIMD3<Float>($0) * job.scale }
        guard points.count >= 2 else { return TubeBuffers() }
        return TubeMesh.buffers(lines: [points], radius: 0.002)
    }

    private func applyPrediction(_ buffers: TubeBuffers) {
        guard predictionActive else { return }
        if let mesh = TubeMesh.mesh(from: buffers) {
            predictionEntity.model = ModelComponent(mesh: mesh, materials: [predictionMaterial])
        } else {
            predictionEntity.model = nil
        }
    }

    private func syncPrediction(_ model: GravityLabModel) {
        guard let inputs = model.heldPredictionInputs() else {
            if predictionActive {
                predictionActive = false
                predictionEntity.model = nil
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
