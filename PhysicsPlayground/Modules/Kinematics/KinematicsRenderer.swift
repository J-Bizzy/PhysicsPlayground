//
//  KinematicsRenderer.swift
//  Physics Playground — Kinematics module
//
//  Renders room-scale projectile motion at 1:1 — physics space is the
//  room: the free-floating launcher and its aim bead, pooled balls with
//  strobe-dot trails and floor shadows, and hoops that light when a ball
//  passes. Two layers wait in More, off by default (2026-10-17): the
//  Trajectory (the predicted arc, its apex and landing marks, the vacuum
//  ghost) and the Numbers (every label and callout). Pools are built once
//  and the per-frame work is transform writes; the arc tube rebuilds only
//  when an aim input changes while it is shown, on a GeometryPipeline
//  worker. Pooled slots are renamed to the flight or ring they show;
//  while a hand owns an entity the render loop leaves its transform.
//

import Foundation
import PhysicsCore
import QuartzCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class KinematicsRenderer {
    /// The SpaceView's tap router, behind a box: the pools are built in
    /// `init` before the last stored property is set, so closures capture
    /// the box rather than `self`.
    private final class TapRouter { var route: ((Entity) -> Void)? }
    private let tapRouter: TapRouter
    var onObjectTap: ((Entity) -> Void)? {
        get { tapRouter.route }
        set { tapRouter.route = newValue }
    }

    /// Root of everything we render, added to RealityView content at identity.
    let root = Entity()
    /// Freeze sculpts: a paused flight grows its velocity and force
    /// arrows — the frozen arc becomes a diagram you walk around.
    private let frozenVectors = FrozenVectors(budget: 24)
    private var lookCallout: Callout?
    var subscriptions: [EventSubscription] = []

    /// Called from the SpaceView's `onDisappear`: subscriptions and
    /// geometry jobs outlive this object and must be cancelled explicitly.
    func teardown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        arcPipeline?.cancel()
        pathPipeline?.cancel()
        ghostPipeline?.cancel()
    }

    static let launcherName = "launcher"
    /// An arc label the rate limit held back, to be offered again.
    private var annotationsPending = false
    static let aimBeadName = "aimBead"

    /// The ball already acknowledged with a pickup pulse — one flash per
    /// grab, not one per frame.
    private var pulsedGrabID: UUID?
    /// Where the release tick plays from when the grab ends; the model's
    /// throw-whoosh fires only on a thrown release.
    private weak var pulsedGrabEntity: Entity?

    private static let barrelLength = Float(KinematicsModel.barrelLength)
    /// The aim bead is the launch velocity: its direction from the
    /// launcher is the aim, its distance the speed — just past the muzzle
    /// at the slowest throw, 80 cm out at the fastest.
    static let beadNear: Float = 0.36
    static let beadFar: Float = 0.80

    static func beadDistance(forSpeed speed: Double) -> Float {
        let range = KinematicsModel.speedRange
        let t = (min(max(speed, range.lowerBound), range.upperBound) - range.lowerBound)
            / (range.upperBound - range.lowerBound)
        return beadNear + (beadFar - beadNear) * Float(t)
    }

    static func speed(forBeadDistance distance: Float) -> Double {
        let range = KinematicsModel.speedRange
        let t = Double(min(max((distance - beadNear) / (beadFar - beadNear), 0), 1))
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }
    private static let baseBallRadius: Float = 0.05
    private static let baseShadowRadius: Float = 0.05

    /// The thin line from the muzzle to the aim bead: the launch velocity
    /// drawn as a vector.
    private let velocityShaft = ModelEntity(
        mesh: Primitives.cylinder(height: 1, radius: 0.0025),
        materials: [Materials.unlit(UIColor(white: 1, alpha: 1), opacity: 0.7)])
    private let launcherBase: ModelEntity
    private let barrel: ModelEntity
    private let bead: ModelEntity
    private let arcEntity = ModelEntity()
    private let arcMaterial: UnlitMaterial
    /// The arc's near-black casing, swept fatter and drawn beneath the
    /// core: a pale line over a cream wall has no contrast.
    private let arcCasingEntity = ModelEntity()
    private let arcCasingMaterial =
        Materials.contrastLine(DesignTokens.Palette.predictedArcUI).casing
    /// Ghost arcs in the arc's own colour at a fraction of its opacity: the
    /// two aim solutions for the hoop being aimed at, and the vacuum arc
    /// while the air is on. One mesh, rebuilt only when their inputs change.
    private let ghostEntity = ModelEntity()
    private let ghostCasingEntity = ModelEntity()
    /// A ghost's casing at the ghost's own strength: the full arc casing
    /// under a 0.22 core read darker than the arc it is a ghost of.
    private let ghostCasingMaterial = Materials.contrastLine(
        DesignTokens.Palette.predictedArcUI, casingOpacity: 0.22).casing
    private let ghostMaterial: UnlitMaterial = {
        let material = Materials.unlit(DesignTokens.Palette.predictedArcUI, opacity: 0.22)
        return material
    }()
    private var ghostPipeline: GeometryPipeline<[[SIMD3<Float>]], ArcTube>?
    /// Core radius of the predicted-arc tube; the casing is swept from
    /// it. `nonisolated` because the pipeline's compute closure reads it
    /// off the main actor.
    private nonisolated static let arcRadius: Float = 0.004

    private let ballPool: EntityPool<ModelEntity>
    private var ballMaterialKeys: [String] = []
    /// Which flight each pooled ball is named for; compare UUIDs, not
    /// strings.
    private var ballSlotIDs: [UUID?] = []
    /// The scale each pooled ball's touch target was last sized for.
    private var ballColliderScales: [Int: Float] = [:]
    private var appliedTextureVersion = -1
    private let audioEmitter = Entity()
    private var lastSoundID = 0
    private let dotPool: EntityPool<Void>
    private let shadowPool: EntityPool<Void>

    private struct RingSlot {
        let tube: ModelEntity
        /// The aim callout over the hoop — "low 23° · high 67°", or why not —
        /// shown only on the hoop being aimed at.
        let aimLabel: BackedLabel
        var appliedID: UUID?
        var appliedPasses = -1
        var appliedAimText = ""
        var flashUntil = 0.0
        var appliedFlashing = false
    }
    private let ringPool: EntityPool<ModelEntity>
    private var ringSlots: [RingSlot] = []
    private let ringMaterial: PhysicallyBasedMaterial
    private let ringFlashMaterial: PhysicallyBasedMaterial

    private var arcPipeline: GeometryPipeline<[SIMD3<Float>], ArcTube>?

    // The Time Capsule's recorded paths, drawn as a walkable tube while the
    // room is scrubbed, in the balls' own orange: a trajectory that
    // happened, where the white arc is one predicted.
    private let pathEntity = ModelEntity()
    private let pathCasingEntity = ModelEntity()
    private let pathMaterial: UnlitMaterial
    private let pathCasingMaterial =
        Materials.contrastLine(DesignTokens.Palette.projectileUI).casing
    private nonisolated static let pathRadius: Float = 0.0035
    private var pathPipeline: GeometryPipeline<[[SIMD3<Float>]], ArcTube>?
    /// The scrub nonce the tube was last built for. Nothing records while
    /// paused, so the recorded window only changes when a restore does.
    private var lastPathNonce: Int?

    // The trajectory's marks: peak height at the apex with a drop line,
    // range and flight time on the landing ring. Placed with the arc; shown
    // by the layers (`applyLayers`).
    private let apexMarker = Entity()
    private var apexLabel: BackedLabel!
    private var apexDropLine: ModelEntity!
    private let landingMarker = Entity()
    private var landingLabel: BackedLabel!
    /// Whether the current prediction has an apex worth marking and a
    /// landing to mark — the arc's facts, kept apart from whether they show.
    private var apexAvailable = false
    private var landingAvailable = false
    /// The launch velocity in words, "45° · 6.0 m/s", beside the bead that
    /// sets it: one reading where a protractor, its needle and two labels
    /// were (2026-10-17). Shown with the Numbers, or while the bead is held.
    private let beadReadingPivot = Entity()
    private var beadReading: BackedLabel!
    private var beadReadingText = ""
    /// Whether a hand holds the aim bead — set by the SpaceView's drag, so a
    /// handle shows its value while you handle it, whatever the Numbers say.
    var beadHeld = false

    /// What a hand carries that is not a ball — the launcher, its aim bead,
    /// a hoop — by entity name. It wears the glow while held and ticks as it
    /// is taken and let go, as a ball always did (2026-11-02); a hoop just
    /// pulled from its well is found once it is drawn, and its tick is the
    /// well's pop.
    let carried = Grasp.Carried()
    /// How large each flight's strobe dots are drawn, easing to 0 when they
    /// are no longer kept (`flightsKeepingDots`).
    private var dotScales: [UUID: Float] = [:]
    /// The flight numbers' white — passed to each BackedLabel, whose
    /// plate now carries the contrast the 0.92 alpha used to gesture at.
    private static let annotationWhite = UIColor(white: 1, alpha: 1)

    // Change detection: the arc tube only rebuilds when these differ.
    private struct ArcInputs: Equatable {
        var aim: SIMD3<Double>
        var speed: Double
        var launcher: SIMD3<Double>
        var gravity: Double
        var air: Bool
        var windSpeed: Double
        var windDirection: Double
        var projectile: Projectile
    }
    private var lastArcInputs: ArcInputs?
    private struct GhostInputs: Equatable {
        var arc: ArcInputs
        var target: UUID?
        var hoop: SIMD3<Double>?
        var trajectory: Bool
    }
    private var lastGhostInputs: GhostInputs?

    init() {
        // First, and as a local: everything below is built before the last
        // stored property is set.
        let router = TapRouter()
        tapRouter = router

        root.addChild(Lighting.keyLight())
        // Launcher: grabbable base sphere, barrel, aim bead — siblings at
        // room coordinates so manipulation never fights a parent transform.
        let launcherMaterial = Materials.machined(DesignTokens.Palette.launcherUI)
        launcherBase = ModelEntity(
            mesh: Primitives.sphere(radius: 0.05), materials: [launcherMaterial])
        launcherBase.name = Self.launcherName
        Grabbable.configureTouchTarget(
            launcherBase, collisionRadius: 0.062,
            activate: { [weak launcherBase] in
                guard let launcherBase else { return }
                router.route?(launcherBase)
            })
        Self.setAccessibility(on: launcherBase, label: "Launcher. Drag to move it anywhere in the room.")
        root.addChild(launcherBase)

        barrel = ModelEntity(
            mesh: Primitives.cylinder(height: Self.barrelLength, radius: 0.02),
            materials: [launcherMaterial]
        )
        if let loaded = PropCache.instance(named: "LauncherBarrel") {
            // Blender-authored barrel: 0.30 m base-to-muzzle along +Y.
            // Centered and scaled onto the aiming entity; the procedural
            // cylinder bows out.
            barrel.model = nil
            loaded.scale = SIMD3(repeating: Self.barrelLength / 0.30)
            loaded.position = [0, -Self.barrelLength / 2, 0]
            barrel.addChild(loaded)
        }
        root.addChild(barrel)

        bead = ModelEntity(
            mesh: Primitives.sphere(radius: 0.026),
            materials: [Materials.energized(DesignTokens.Palette.projectileUI, glow: 0.25)]
        )
        bead.name = Self.aimBeadName
        Grabbable.configureTouchTarget(
            bead, collisionRadius: 0.040,
            activate: { [weak bead] in
                guard let bead else { return }
                router.route?(bead)
            })
        Self.setAccessibility(on: bead, label: "Aim bead. Drag to point the launcher.")
        root.addChild(bead)
        // Decoration on the vector, never a target: the bead is the handle.
        velocityShaft.name = "velocity-shaft"
        root.addChild(velocityShaft)

        // Predicted arc. Casing first, core second: darkness under light.
        let arcMaterial = Materials.unlit(DesignTokens.Palette.predictedArcUI, opacity: 0.5)
        self.arcMaterial = arcMaterial
        arcEntity.name = "predicted-arc"
        arcCasingEntity.name = "predicted-arc-casing"
        arcEntity.isEnabled = false
        arcCasingEntity.isEnabled = false
        root.addChild(arcCasingEntity)
        root.addChild(arcEntity)
        ghostEntity.name = "ghost-arcs"
        ghostEntity.isEnabled = false
        ghostCasingEntity.isEnabled = false
        root.addChild(ghostCasingEntity)
        root.addChild(ghostEntity)

        // The recorded paths, same casing recipe, disabled until a scrub.
        let recorded = Materials.unlit(DesignTokens.Palette.projectileUI, opacity: 0.6)
        pathMaterial = recorded
        pathEntity.isEnabled = false
        pathCasingEntity.isEnabled = false
        root.addChild(pathCasingEntity)
        root.addChild(pathEntity)

        // Balls: unit sphere scaled per projectile, grabbable for throwing.
        let ballMesh = Primitives.sphere(radius: Self.baseBallRadius)
        ballPool = EntityPool(budget: KinematicsModel.flightBudget) { container in
            let sphere = ModelEntity(
                mesh: ballMesh,
                materials: [Materials.energized(DesignTokens.Palette.projectileUI,
                                                glow: 0)]
            )
            // The factor survives the per-ball scale, so a basketball's target
            // stays out of the other balls' flight paths.
            Grabbable.configureTouchTarget(
                sphere, collisionRadius: Self.baseBallRadius * 1.15,
                activate: { [weak sphere] in
                    guard let sphere else { return }
                    router.route?(sphere)
                })
            Self.setAccessibility(on: sphere, label: "Ball. Grab and throw it.")
            container.addChild(sphere)
            return sphere
        }
        ballMaterialKeys = Array(repeating: "", count: ballPool.budget)
        ballSlotIDs = Array(repeating: nil, count: ballPool.budget)
        root.addChild(ballPool.root)
        root.addChild(frozenVectors.root)

        // Strobe dots: equal time intervals are the whole of projectile motion
        // in one picture — constant horizontal spacing, vertical spacing
        // shrinking to nothing at the apex. Opaque, so they read as the strobe
        // photograph they imitate; since 2026-10-17 smaller and quieter, and
        // only the newest flight keeps them once it has landed.
        let dotMaterial = Materials.energized(
            DesignTokens.Palette.projectileUI, roughness: 0.3, glow: 0.35)
        let dotMesh = Primitives.sphere(radius: Self.dotRadius)
        dotPool = EntityPool(
            budget: KinematicsModel.flightBudget * KinematicsModel.dotsPerFlight
        ) { container in
            container.addChild(ModelEntity(mesh: dotMesh, materials: [dotMaterial]))
        }
        root.addChild(dotPool.root)

        // Floor shadows: flat discs under airborne balls — the depth cue
        // that makes height over the real floor readable.
        let shadowMaterial = Materials.unlit(.black, opacity: 0.22)
        let shadowMesh = Primitives.cylinder(height: 0.002, radius: Self.baseShadowRadius)
        shadowPool = EntityPool(budget: KinematicsModel.flightBudget) { container in
            container.addChild(ModelEntity(mesh: shadowMesh, materials: [shadowMaterial]))
        }
        root.addChild(shadowPool.root)

        // Hoops: torus via TubeMesh circle, the aim callout floating above.
        // A crafted target: a glossy, softly-glowing mint hoop that flares
        // bright glowing green the instant a ball drops through it.
        ringMaterial = Materials.energized(DesignTokens.Palette.targetUI,
                                           roughness: 0.2, glow: 0.3)
        ringFlashMaterial = Materials.energized(.systemGreen,
                                                roughness: 0.15, glow: 0.6)

        let circle: [SIMD3<Float>] = (0...32).map { index in
            let angle = 2 * Float.pi * Float(index) / 32
            return SIMD3(cos(angle), 0, sin(angle)) * Float(KinematicsModel.ringRadius)
        }
        let ringMesh = TubeMesh.tube(lines: [circle], radius: 0.02, sides: 8)
        let capturedRingMaterial = ringMaterial
        ringPool = EntityPool(budget: KinematicsModel.ringBudget) { container in
            let tube = ModelEntity(
                mesh: ringMesh ?? Primitives.sphere(radius: 0.05),
                materials: [capturedRingMaterial]
            )
            Grabbable.configureTouchTarget(
                tube, collisionRadius: 0.05,
                activate: { [weak tube] in
                    guard let tube else { return }
                    router.route?(tube)
                })
            // A ring is grabbed by its rim: small colliders hug the torus rather
            // than one fat sphere swallowing every pinch through the opening.
            // Twenty-eight is the first count whose spheres (capped at r 0.034 by
            // the collider rule) cover the tube's own 0.02 m radius in the worst
            // gap.
            let rimCount = 28
            let rim = (0..<rimCount).map { index -> ShapeResource in
                let angle = Float(index) / Float(rimCount) * 2 * .pi
                return Primitives.collisionSphere(radius: 0.034, offset: [
                        cos(angle) * Float(KinematicsModel.ringRadius),
                        0,
                        sin(angle) * Float(KinematicsModel.ringRadius),
                    ])
            }
            tube.components.set(CollisionComponent(shapes: rim))
            Self.setAccessibility(on: tube, label: "Hoop. Drag to place it; a ball passing down through it lights it.")
            container.addChild(tube)
            return tube
        }
        for slot in ringPool.slots {
            let pivot = Entity()
            pivot.position = [0, 0.3, 0]
            pivot.components.set(BillboardComponent())
            slot.entity.addChild(pivot)
            let aim = BackedLabel(size: 0.036)
            aim.root.position = [0, -0.11, 0]
            pivot.addChild(aim.root)
            ringSlots.append(RingSlot(tube: slot.payload, aimLabel: aim))
        }
        root.addChild(ringPool.root)

        audioEmitter.components.set(SpatialAudioComponent())
        root.addChild(audioEmitter)
        BallTextures.warmUp()

        arcPipeline = GeometryPipeline(
            compute: { points in
                ArcTube(
                    core: TubeMesh.buffers(lines: [points], radius: Self.arcRadius),
                    casing: TubeMesh.buffers(
                        lines: [points],
                        radius: Materials.casingRadius(forCore: Self.arcRadius)))
            },
            apply: { [weak self] in self?.applyArc($0) }
        )

        pathPipeline = GeometryPipeline(
            compute: { lines in
                ArcTube(
                    core: TubeMesh.buffers(lines: lines, radius: Self.pathRadius),
                    casing: TubeMesh.buffers(
                        lines: lines,
                        radius: Materials.casingRadius(forCore: Self.pathRadius)))
            },
            apply: { [weak self] in self?.applyRecordedPaths($0) }
        )

        ghostPipeline = GeometryPipeline(
            compute: { lines in
                ArcTube(
                    core: TubeMesh.buffers(lines: lines, radius: Self.arcRadius),
                    casing: TubeMesh.buffers(
                        lines: lines,
                        radius: Materials.casingRadius(forCore: Self.arcRadius)))
            },
            apply: { [weak self] in self?.applyGhost($0) }
        )

        buildFlightAnnotations()
    }

    // MARK: Spatial flight numbers

    private func buildFlightAnnotations() {
        // Apex: a dot on the arc's crest, the height beside it, and a
        // faint plumb line to the floor — the number drawn as geometry.
        let apexDot = ModelEntity(
            mesh: Primitives.sphere(radius: 0.009),
            materials: [UnlitMaterial(color: DesignTokens.Palette.predictedArcUI)])
        apexMarker.addChild(apexDot)
        let apexPivot = Entity()
        apexPivot.components.set(BillboardComponent())
        apexPivot.position = [0, 0.055, 0]
        apexLabel = BackedLabel(size: 0.042)
        apexPivot.addChild(apexLabel.root)
        apexMarker.addChild(apexPivot)
        apexMarker.isEnabled = false
        root.addChild(apexMarker)

        let plumbMaterial = Materials.unlit(.white, opacity: 0.16)
        apexDropLine = ModelEntity(
            mesh: Primitives.cylinder(height: 1, radius: 0.0012),
            materials: [plumbMaterial])
        apexDropLine.isEnabled = false
        root.addChild(apexDropLine)

        // Landing: a floor ring where the flight will end, wearing the
        // range and flight time.
        let circle: [SIMD3<Float>] = (0...28).map { index in
            let angle = 2 * Float.pi * Float(index) / 28
            return SIMD3(cos(angle), 0, sin(angle)) * 0.07
        }
        let ringMaterial = Materials.unlit(DesignTokens.Palette.predictedArcUI, opacity: 0.55)
        if let ringMesh = TubeMesh.tube(lines: [circle], radius: 0.0035, sides: 4) {
            landingMarker.addChild(ModelEntity(mesh: ringMesh, materials: [ringMaterial]))
        }
        let landingPivot = Entity()
        landingPivot.components.set(BillboardComponent())
        landingPivot.position = [0, 0.075, 0]
        landingLabel = BackedLabel(size: 0.042)
        landingPivot.addChild(landingLabel.root)
        landingMarker.addChild(landingPivot)
        landingMarker.isEnabled = false
        root.addChild(landingMarker)
        apexMarker.name = "apex-marker"
        landingMarker.name = "landing-marker"

        // The bead's reading, billboarded beside it.
        beadReadingPivot.name = "bead-reading"
        beadReadingPivot.components.set(BillboardComponent())
        beadReading = BackedLabel(size: 0.036)
        beadReadingPivot.addChild(beadReading.root)
        beadReadingPivot.isEnabled = false
        root.addChild(beadReadingPivot)
    }

    /// A launch velocity as the room writes it, "45° · 6.0 m/s" — the
    /// launcher's bead and a hand's throw read the same way.
    nonisolated static func launchText(elevationDegrees: Double, speed: Double) -> String {
        PhysicsFormat.angle(elevationDegrees, decimals: 0) + " · "
            + PhysicsFormat.measurement(speed, "m/s", decimals: 1)
    }

    /// The strobe dot's radius: 8 mm since 2026-10-17 (it was 13).
    nonisolated static let dotRadius: Float = 0.008

    /// Which flights keep their strobe dots: every ball still flying or
    /// rolling, and the newest launch that has any once it has landed. The
    /// older ones shrink away as the next ball leaves — by what has
    /// happened, not by a clock, so a pause or a scrub keeps the picture.
    nonisolated static func flightsKeepingDots(_ flights: [KinematicsModel.Flight]) -> Set<UUID> {
        var kept = Set(flights.filter { $0.status == .flying || $0.status == .rolling }.map(\.id))
        if let newest = flights.filter({ !$0.dots.isEmpty }).max(by: { $0.launchSerial < $1.launchSerial }) {
            kept.insert(newest.id)
        }
        return kept
    }

    /// Places the trajectory's apex and landing marks and writes their
    /// labels. Whether they show is `applyLayers`' business: this records
    /// only whether the prediction has an apex and a landing to mark.
    /// Returns whether every label took its text; false means the rate limit
    /// held one back, and the caller offers the annotations again next frame.
    @discardableResult
    private func updateFlightAnnotations(
        _ model: KinematicsModel, trajectory: ProjectileMotion.Trajectory,
        vacuum: ProjectileMotion.Trajectory? = nil
    ) -> Bool {
        var shown = true
        // Peak height, where the peak actually is.
        if let apex = trajectory.points.max(by: { $0.y < $1.y }), apex.y > 0.3 {
            apexAvailable = true
            apexMarker.position = SIMD3<Float>(apex)
            shown = apexLabel.setText(
                PhysicsFormat.measurement(trajectory.apexHeight, "m", decimals: 1),
                color: Self.annotationWhite) && shown
            apexDropLine.position = SIMD3(Float(apex.x), Float(apex.y) / 2, Float(apex.z))
            apexDropLine.scale = SIMD3(1, Float(apex.y), 1)
        } else {
            apexAvailable = false
        }

        // Range and flight time, at the landing spot.
        if trajectory.landed, let landing = trajectory.landingPoint {
            landingAvailable = true
            landingMarker.position = SIMD3(Float(landing.x), 0.004, Float(landing.z))
            // With the air on, the vacuum range stands beside the real
            // one: the gap between the two numbers is drag.
            var text = PhysicsFormat.measurement(trajectory.range, "m", decimals: 1) + " · "
                + PhysicsFormat.measurement(trajectory.flightTime, "s", decimals: 1)
            if let vacuum, vacuum.landed {
                text += " · vacuum " + PhysicsFormat.measurement(vacuum.range, "m", decimals: 1)
            }
            shown = landingLabel.setText(text, color: Self.annotationWhite) && shown
        } else {
            landingAvailable = false
        }
        return shown
    }

    /// The two layers, faded every frame rather than switched when what
    /// they show changes (2026-11-02): a layer from More, and the apex and
    /// landing as the arc comes to have them, come and go as everything
    /// else in the room does. `Fade.tick` writes nothing once settled.
    private func applyLayers(_ model: KinematicsModel) {
        let trajectory = model.showsTrajectory, numbers = model.showsNumbers
        Fade.tick(arcEntity, visible: trajectory)
        Fade.tick(arcCasingEntity, visible: trajectory)
        Fade.tick(apexMarker, visible: trajectory && apexAvailable)
        Fade.tick(apexDropLine, visible: trajectory && apexAvailable)
        Fade.tick(landingMarker, visible: trajectory && landingAvailable)
        Fade.tick(apexLabel.root, visible: numbers)
        Fade.tick(landingLabel.root, visible: numbers)
    }

    /// The bead's reading: placed every frame (a transform) beside the bead,
    /// on the side of the aim line the arc never bends toward; its text
    /// regenerated only when a displayed digit moves.
    private func syncBeadReading(_ model: KinematicsModel) {
        let visible = model.showsNumbers || beadHeld
        if beadReadingPivot.isEnabled != visible { beadReadingPivot.isEnabled = visible }
        guard visible else { return }
        let aim = SIMD3<Float>(model.aimDirection)
        let lift = simd_normalize(SIMD3<Float>(0, 1, 0) - aim * aim.y)
        beadReadingPivot.position = SIMD3<Float>(model.launcherPosition)
            + Self.beadDistance(forSpeed: model.launchSpeed) * aim + 0.08 * lift
        let text = Self.launchText(elevationDegrees: model.elevationDegrees,
                                   speed: model.launchSpeed)
        if text != beadReadingText,
           beadReading.setText(text, color: Self.annotationWhite) {
            beadReadingText = text
        }
    }

    /// Both passes of the arc, built off-thread together so the casing
    /// can never lag a frame behind the line it underwrites, and written
    /// into each entity's mesh in place (`LiveTube`): dragging the bead
    /// re-meshes the arc every frame.
    private nonisolated struct ArcTube: Sendable {
        var core = TubeBuffers()
        var casing = TubeBuffers()
    }

    private func applyArc(_ tube: ArcTube) {
        LiveTube.apply(tube.core, to: arcEntity, material: arcMaterial)
        LiveTube.apply(tube.casing, to: arcCasingEntity, material: arcCasingMaterial)
    }

    private func applyGhost(_ tube: ArcTube) {
        LiveTube.apply(tube.core, to: ghostEntity, material: ghostMaterial)
        LiveTube.apply(tube.casing, to: ghostCasingEntity, material: ghostCasingMaterial)
    }

    private func applyRecordedPaths(_ tube: ArcTube) {
        LiveTube.apply(tube.core, to: pathEntity, material: pathMaterial)
        LiveTube.apply(tube.casing, to: pathCasingEntity, material: pathCasingMaterial)
    }

    /// The recorded-path tube exists exactly while the room is scrubbed.
    /// Rebuilt only when the restore nonce moves — nothing records while
    /// paused, so a scrub drag changes which instant the balls show, not
    /// the window the tube draws.
    private func syncRecordedPaths(_ model: KinematicsModel) {
        guard model.scrubTime != nil else {
            pathEntity.isEnabled = false
            pathCasingEntity.isEnabled = false
            lastPathNonce = nil
            return
        }
        if lastPathNonce == nil {
            pathPipeline?.submit(model.capsuleRecordedPaths())
        }
        lastPathNonce = model.scrubNonce
        pathEntity.isEnabled = true
        pathCasingEntity.isEnabled = true
    }

    // MARK: Per-frame tick (from SceneEvents.Update)

    // MARK: The catch readout

    /// What the ball was doing at the instant it hit your hand, floating
    /// at the ball rather than parked on a distant card.
    private var catchCallout: Callout?
    private var lastCatchID: UUID?
    private var catchShownAt: Double = -100

    private func syncCatch(_ model: KinematicsModel) {
        if catchCallout == nil {
            let callout = Callout(color: DesignTokens.Palette.projectileUI,
                                  textSize: 0.026, offset: SIMD3(0, 0.14, 0))
            callout.setAccessibilityName("Catch")
            catchCallout = callout
            root.addChild(callout.root)
        }
        // A catch counts as shown once the callout has taken its text.
        if let caught = model.lastCatch, caught.id != lastCatchID {
            catchCallout?.anchor(at: SIMD3<Float>(caught.position))
            let text = "Caught\n"
                + PhysicsFormat.measurement(caught.speed, "m/s", decimals: 2) + "   "
                + PhysicsFormat.measurement(caught.height, "m", decimals: 2) + "\n"
                + PhysicsFormat.measurement(caught.flightTime, "s", decimals: 2) + "   "
                + PhysicsFormat.measurement(caught.kineticEnergy, "J", decimals: 3)
            if catchCallout?.setText(text) == true {
                lastCatchID = caught.id
                catchShownAt = CACurrentMediaTime()
            }
        }
        // The readout lingers a few seconds, then bows out — and is one of
        // the Numbers.
        catchCallout?.isEnabled = model.showsNumbers && CACurrentMediaTime() - catchShownAt < 4.5
    }

    func tick(_ model: KinematicsModel) {
        carried.find(under: root)
        tickFlightCallout(model)
        tickReleaseCallout(model)
        syncReadyBall(model)
        frozenVectors.update(frozen: model.isPaused, dt: 1.0 / 90) {
            var samples: [FrozenVectors.Sample] = []
            for flight in model.flights
            where flight.status == .flying || flight.status == .rolling {
                let position = SIMD3<Float>(flight.state.position)
                let velocity = flight.state.velocity
                let speed = simd_length(velocity)
                if speed > 0.01 {
                    samples.append(.init(
                        position: position,
                        direction: SIMD3<Float>(velocity / speed),
                        magnitude01: Float(min(speed / 12, 1)),
                        kind: .velocity))
                }
                // The honest net force: the same acceleration law the
                // integrator flies the ball with, gravity plus drag.
                let drag = model.airResistance
                    ? ProjectileMotion.Drag(projectile: flight.projectile,
                                            wind: model.wind)
                    : nil
                let acceleration = ProjectileMotion.acceleration(
                    velocity: velocity, gravity: model.gravity, drag: drag)
                let a = simd_length(acceleration)
                if a > 0.01 {
                    samples.append(.init(
                        position: position,
                        direction: SIMD3<Float>(acceleration / a),
                        magnitude01: Float(min(a / (2 * 9.81), 1)),
                        kind: .force))
                }
            }
            return samples
        }
        syncCatch(model)
        // Fresh procedural textures arrived: reapply ball materials.
        if appliedTextureVersion != BallTextures.version {
            appliedTextureVersion = BallTextures.version
            ballMaterialKeys = Array(repeating: "", count: ballPool.budget)
        }

        // Spatial sounds requested by the model.
        if let event = model.soundEvent, event.id != lastSoundID {
            lastSoundID = event.id
            audioEmitter.position = SIMD3<Float>(event.position)
            SoundPalette.play(event.kind, on: audioEmitter, volume: event.volume)
        }

        let aim = SIMD3<Float>(model.aimDirection)
        let launcher = SIMD3<Float>(model.launcherPosition)

        launcherBase.position = launcher
        barrel.orientation = VectorFieldArrows.rotationFromYAxis(to: aim)
        barrel.position = launcher + (Self.barrelLength / 2) * aim
        let reach = Self.beadDistance(forSpeed: model.launchSpeed)
        bead.position = launcher + reach * aim
        // The vector's shaft, from the muzzle to the bead: the longer it is,
        // the faster the shot.
        let muzzle = Self.barrelLength
        velocityShaft.position = launcher + (muzzle + reach) / 2 * aim
        velocityShaft.orientation = VectorFieldArrows.rotationFromYAxis(to: aim)
        velocityShaft.scale = SIMD3(1, max(reach - muzzle, 0.001), 1)

        // Predicted arc — rebuilt only when an input changed, and only while
        // the Trajectory is shown. Hidden, the last inputs stay, so showing it
        // again rebuilds only if the aim moved meanwhile.
        let arcInputs = ArcInputs(
            aim: model.aimDirection, speed: model.launchSpeed,
            launcher: model.launcherPosition, gravity: model.gravity,
            air: model.airResistance, windSpeed: model.windSpeed,
            windDirection: model.windDirectionDegrees, projectile: model.projectile
        )
        if !model.showsTrajectory {
            // Nothing to place.
        } else if arcInputs != lastArcInputs {
            lastArcInputs = arcInputs
            // The RK4 trace is microseconds (see the model); the tube's
            // vertex math is what moves to the worker.
            let trajectory = model.prediction
            arcPipeline?.submit(trajectory.points.map { SIMD3<Float>($0) })
            annotationsPending = !updateFlightAnnotations(
                model, trajectory: trajectory, vacuum: model.vacuumPrediction)
        } else if annotationsPending {
            // The aim stopped inside the labels' rate limit: the last
            // numbers land now rather than when the aim next moves.
            annotationsPending = !updateFlightAnnotations(
                model, trajectory: model.prediction, vacuum: model.vacuumPrediction)
        }

        applyLayers(model)
        syncBeadReading(model)

        // Ghost arcs: the aim solutions for the hoop being aimed at (an
        // explicit request, so whatever the layers say), and the vacuum arc
        // while the air is on and the Trajectory shown. Rebuilt on a change
        // of inputs only — the solve is memoised in the model, the tubes are
        // not free.
        let ghostInputs = GhostInputs(
            arc: arcInputs, target: model.aimTargetID,
            hoop: model.aimTargetID.flatMap { id in
                model.rings.first { $0.id == id }?.position
            },
            trajectory: model.showsTrajectory)
        if ghostInputs != lastGhostInputs {
            lastGhostInputs = ghostInputs
            var lines: [[SIMD3<Float>]] = []
            if let id = model.aimTargetID {
                for solution in [KinematicsModel.AimSolution.low, .high] {
                    if let arc = model.solutionArc(solution, for: id) {
                        lines.append(arc.points.map { SIMD3<Float>($0) })
                    }
                }
            }
            if model.showsTrajectory, let vacuum = model.vacuumPrediction {
                lines.append(vacuum.points.map { SIMD3<Float>($0) })
            }
            ghostEntity.isEnabled = !lines.isEmpty
            ghostCasingEntity.isEnabled = !lines.isEmpty
            if !lines.isEmpty { ghostPipeline?.submit(lines) }
        }

        syncFlights(model.flights)
        syncRings(model)
        syncRecordedPaths(model)
    }

    // MARK: Balls, dots, shadows

    /// The live readout rides the newest ball still in flight — every
    /// throw gets its own speed and height following it, no gaze
    /// required. (This replaced a gaze-revealed callout, which the
    /// simulator could never show and a device user never found.)
    private var flightCalloutReveal: Float = 0
    /// The reveal last written and the reading last formatted — gates on
    /// per-frame work that used to run regardless of whether anything
    /// displayed had changed. NaN keys force the first write.
    private var appliedFlightCalloutReveal: Float = -1
    private var flightCalloutKey: (Double, Double) = (.nan, .nan)

    private func tickFlightCallout(_ model: KinematicsModel) {
        let flight = model.flights.last { $0.status == .flying || $0.status == .rolling }
        let target: Float = flight != nil && model.showsNumbers ? 1 : 0
        flightCalloutReveal += (target - flightCalloutReveal) * 0.12
        guard let flight, flightCalloutReveal > 0.02 else {
            lookCallout?.isEnabled = false
            return
        }
        if lookCallout == nil {
            let callout = Callout(color: UIColor(DesignTokens.Palette.kinematicsAccent),
                                  textSize: 0.022, offset: SIMD3(0, 0.10, 0))
            callout.setAccessibilityName("Ball in flight")
            root.addChild(callout.root)
            lookCallout = callout
        }
        lookCallout?.isEnabled = true
        // Opacity written only while the reveal eases; the anchor is a
        // transform and stays per-frame.
        if abs(flightCalloutReveal - appliedFlightCalloutReveal) > 0.0005 {
            appliedFlightCalloutReveal = flightCalloutReveal
            lookCallout?.root.components.set(
                OpacityComponent(opacity: flightCalloutReveal))
        }
        lookCallout?.anchor(at: SIMD3<Float>(flight.state.position))
        // Formatted only when a displayed decimal moves — the mesh is
        // deduped downstream, the string was not.
        let key = ((Double(simd_length(flight.state.velocity)) * 10).rounded(),
                   (Double(max(flight.state.position.y, 0)) * 10).rounded())
        if key != flightCalloutKey,
           lookCallout?.setText(
               PhysicsFormat.measurement(Double(simd_length(flight.state.velocity)),
                                         "m/s", decimals: 1)
               + " · "
               + PhysicsFormat.measurement(Double(max(flight.state.position.y, 0)),
                                           "m", decimals: 1)
               + " up") == true {
            flightCalloutKey = key
        }
    }

    // MARK: The throw's own protractor

    /// Where your hand let the ball go, with the angle and speed it set:
    /// the launcher's "45° · 6.0 m/s", read off your arm (2026-10-17). It
    /// hangs at the release point while that ball flies and rolls — the
    /// readout riding the ball is the ball now, this is the throw then —
    /// and below it, so the two never sit on one another as the ball leaves.
    private var releaseCallout: Callout?
    private var releaseCalloutReveal: Float = 0
    private var appliedReleaseCalloutReveal: Float = -1
    private var releaseCalloutText = ""

    nonisolated static func releaseText(_ release: KinematicsModel.Flight.Release) -> String {
        launchText(elevationDegrees: release.elevationDegrees, speed: release.speed)
    }

    private func tickReleaseCallout(_ model: KinematicsModel) {
        let thrown = model.latestThrow
        let live = model.showsNumbers
            && (thrown.map { $0.status == .flying || $0.status == .rolling } ?? false)
        releaseCalloutReveal += ((live ? 1 : 0) - releaseCalloutReveal) * 0.12
        guard let release = thrown?.release, releaseCalloutReveal > 0.02 else {
            releaseCallout?.isEnabled = false
            return
        }
        if releaseCallout == nil {
            let callout = Callout(color: UIColor(DesignTokens.Palette.kinematicsAccent),
                                  textSize: 0.022, offset: SIMD3(0, -0.10, 0))
            callout.setAccessibilityName("Your throw")
            root.addChild(callout.root)
            releaseCallout = callout
        }
        releaseCallout?.isEnabled = true
        if abs(releaseCalloutReveal - appliedReleaseCalloutReveal) > 0.0005 {
            appliedReleaseCalloutReveal = releaseCalloutReveal
            releaseCallout?.root.components.set(OpacityComponent(opacity: releaseCalloutReveal))
        }
        releaseCallout?.anchor(at: SIMD3<Float>(release.position))
        let text = Self.releaseText(release)
        if text != releaseCalloutText, releaseCallout?.setText(text) == true {
            releaseCalloutText = text
        }
    }

    private func syncFlights(_ flights: [KinematicsModel.Flight]) {
        // The ball in a hand, read off the model. Until 2026-10-14 this keyed
        // on a manipulation flag nothing set, so a grab here never flashed or
        // ticked while Pendulums' and Circuits' did.
        let heldID = flights.first { $0.status == .held }?.id
        if heldID == nil {
            if pulsedGrabID != nil, let entity = pulsedGrabEntity {
                LiveGlow.set(false, on: entity)
                SoundPalette.play(.releaseTick, on: entity, volume: 0.18)
            }
            pulsedGrabID = nil
            pulsedGrabEntity = nil
        }
        // A ball cleared or evicted fades where it was; its slot goes
        // straight on to show the next.
        let flying = Set(flights.map(\.id))
        for (index, slot) in ballPool.slots.enumerated() {
            if let shown = ballSlotIDs[index], !flying.contains(shown) {
                Retire.copy(of: slot.entity)
                ballSlotIDs[index] = nil
            }
        }
        for (index, slot) in ballPool.slots.enumerated() {
            guard index < flights.count else {
                slot.entity.isEnabled = false
                continue
            }
            let flight = flights[index]
            slot.entity.isEnabled = true

            // The slot represents this flight now: rename so manipulation
            // events route to the right model object.
            if ballSlotIDs[index] != flight.id {
                ballSlotIDs[index] = flight.id
                slot.payload.name = flight.id.uuidString
            }
            applyBallMaterial(for: flight.projectile, at: index, slot: slot)

            let radius = max(Float(flight.projectile.diameter / 2), 0.008)
            let ballScale = radius / Self.baseBallRadius
            slot.entity.scale = SIMD3<Float>(repeating: ballScale)
            // Re-sized with the ball so a table-tennis ball keeps the same reach as
            // a basketball; change-gated because it allocates. On `slot.payload`,
            // the sphere carrying the input target.
            if abs((ballColliderScales[index] ?? -1) - ballScale) > 1e-4 {
                ballColliderScales[index] = ballScale
                slot.payload.components.set(CollisionComponent(shapes: [
                    Primitives.collisionSphere(radius: Grabbable.sphereTargetRadius(
                        baseRadius: Self.baseBallRadius, scale: ballScale)),
                ]))
            }

            if flight.id == heldID, pulsedGrabID != flight.id {
                // Acknowledged once per grab. The model carries the held ball
                // (`holdBall`), so its transform is written like any other.
                pulsedGrabID = flight.id
                // Live while held: the glow stays until the hand lets go.
                if let previous = pulsedGrabEntity, previous !== slot.entity {
                    LiveGlow.set(false, on: previous)
                }
                pulsedGrabEntity = slot.entity
                LiveGlow.set(true, on: slot.entity)
                SoundPalette.play(.grabTick, on: slot.entity, volume: 0.2)
            }
            slot.entity.position = SIMD3<Float>(flight.state.position)
            // Undo any offset the manipulation system left on the child.
            slot.payload.position = .zero

            // Cosmetic tumble in flight / roll on the ground: rotate
            // about the horizontal axis perpendicular to the motion.
            let velocity = flight.state.velocity
            let speed = simd_length(velocity)
            if (flight.status == .flying || flight.status == .rolling), speed > 0.05 {
                let axis: SIMD3<Double> = simd_normalize(SIMD3(velocity.z, 0, -velocity.x))
                let cappedSpeed: Double = min(speed, 8)
                let effectiveRadius: Double = max(Double(radius), 0.02)
                let angle: Double = cappedSpeed / effectiveRadius * (0.6 / 90.0)
                slot.payload.orientation =
                    simd_quatf(angle: Float(angle), axis: SIMD3<Float>(axis))
                    * slot.payload.orientation
            }

            // Shadow directly below, hidden once the ball rests on the floor.
            let shadow = shadowPool.slots[index]
            let onFloor = flight.status == .rested || flight.status == .rolling
            shadow.entity.isEnabled = !onFloor
            if !onFloor {
                shadow.entity.position = SIMD3(
                    Float(flight.state.position.x), 0.001, Float(flight.state.position.z))
                shadow.entity.scale = SIMD3<Float>(repeating: radius / Self.baseShadowRadius)
            }
        }
        for index in flights.count..<ballPool.budget {
            ballPool.slots[index].entity.isEnabled = false
            shadowPool.slots[index].entity.isEnabled = false
        }

        // Each flight's dots ease to full size while it keeps them and away
        // when it does not — a scale, so the per-frame work stays transforms.
        let kept = Self.flightsKeepingDots(flights)
        var live = Set<UUID>()
        var dotIndex = 0
        for flight in flights where !flight.dots.isEmpty {
            live.insert(flight.id)
            let target: Float = kept.contains(flight.id) ? 1 : 0
            var scale = dotScales[flight.id] ?? target
            scale += (target - scale) * 0.12
            if abs(scale - target) < 0.01 { scale = target }
            dotScales[flight.id] = scale
            guard scale > 0.02 else { continue }
            for dot in flight.dots where dotIndex < dotPool.budget {
                let slot = dotPool.slots[dotIndex]
                slot.entity.isEnabled = true
                slot.entity.position = SIMD3<Float>(dot)
                slot.entity.scale = SIMD3(repeating: scale)
                dotIndex += 1
            }
        }
        dotScales = dotScales.filter { live.contains($0.key) }
        for index in dotIndex..<dotPool.budget {
            dotPool.slots[index].entity.isEnabled = false
        }
    }

    private func applyBallMaterial(for projectile: Projectile, at index: Int, slot: EntityPool<ModelEntity>.Slot) {
        guard ballMaterialKeys[index] != projectile.name else { return }
        ballMaterialKeys[index] = projectile.name
        slot.payload.model?.materials = [ballMaterial(for: projectile)]
    }

    /// The hoop's miniature for its well mouth: the same torus recipe at
    /// about a quarter size — a token, since the real rim is 46 cm and the
    /// well row's pitch is 13 cm; sized with `ballPreview` so the pair
    /// clears with the wells' breath allowed for.
    static func hoopPreview() -> Entity {
        let circle: [SIMD3<Float>] = (0...32).map { index in
            let angle = 2 * Float.pi * Float(index) / 32
            return SIMD3(cos(angle), 0, sin(angle)) * 0.035
        }
        let mesh = TubeMesh.tube(lines: [circle], radius: 0.005, sides: 8)
            ?? Primitives.sphere(radius: 0.02)
        return ModelEntity(
            mesh: mesh,
            materials: [Materials.energized(DesignTokens.Palette.targetUI,
                                            roughness: 0.2, glow: 0.3)])
    }

    /// What waits in the ball well's mouth: a 6 cm token of the ball you will
    /// throw, in that ball's own skin, following the ball fan (2026-10-17).
    /// The renderer keeps it because the well builds its preview once; the
    /// size is fixed because the well measures its target and name plate
    /// from it. Until then it was a basketball token that fell back to
    /// orange before the textures loaded — the aim bead's orange, so the
    /// ball you throw and the bead you aim with looked like one thing.
    let readyBall = ModelEntity(mesh: Primitives.sphere(radius: 0.03), materials: [])
    private var readyBallKey = ""

    private func syncReadyBall(_ model: KinematicsModel) {
        let key = model.projectile.name + "|\(BallTextures.version)"
        guard key != readyBallKey else { return }
        readyBallKey = key
        readyBall.model?.materials = [ballMaterial(for: model.projectile)]
    }

    private func ballMaterial(for projectile: Projectile) -> RealityKit.Material {
        if let texture = BallTextures.texture(for: projectile.name) {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = .init(floatLiteral: projectile.name == Projectile.cannonball.name ? 0.35 : 0.6)
            material.metallic = .init(floatLiteral: projectile.name == Projectile.cannonball.name ? 0.7 : 0.0)
            return material
        }
        let color: UIColor = switch projectile.name {
        case Projectile.tableTennisBall.name: .white
        case Projectile.golfBall.name: UIColor(white: 0.92, alpha: 1)
        case Projectile.cannonball.name: UIColor(white: 0.18, alpha: 1)
        case Projectile.basketball.name: DesignTokens.Palette.projectileUI
        default: .systemTeal
        }
        return Materials.energized(color, roughness: 0.5, glow: 0)
    }

    // MARK: Hoops

    /// What the hoop being aimed at says about itself: both angles, whole
    /// degrees (so the texture is stable), and "with drag" when the roots
    /// were found rather than derived; or why there is nothing to aim.
    private static func aimText(for ring: KinematicsModel.Ring,
                                in model: KinematicsModel) -> String {
        var parts: [String] = []
        // The monkey-and-hunter latch reads off the hoop itself: a petal's
        // name is fixed at retarget, so the hoop says whether it is armed.
        if ring.dropOnFire { parts.append("drops when fired") }
        if ring.id == model.aimTargetID {
            if let roots = model.solutions(for: ring.id) {
                let low = Int((roots.low * 180 / .pi).rounded())
                let high = Int((roots.high * 180 / .pi).rounded())
                parts.append(low == high ? "one arc · \(low)°" : "low \(low)° · high \(high)°")
                if model.airResistance { parts.append("with drag") }
            } else {
                parts.append("out of range at "
                    + PhysicsFormat.measurement(model.launchSpeed, "m/s", decimals: 1))
            }
        }
        return parts.joined(separator: " · ")
    }

    private func syncRings(_ model: KinematicsModel) {
        let rings = model.rings
        let now = CACurrentMediaTime()
        // A hoop deleted or cleared fades where it was; its slot goes
        // straight on to show the next.
        let live = Set(rings.map(\.id))
        for index in 0..<ringPool.budget {
            if let shown = ringSlots[index].appliedID, !live.contains(shown) {
                Retire.copy(of: ringPool.slots[index].entity)
                ringSlots[index].appliedID = nil
            }
        }
        for index in 0..<ringPool.budget {
            let poolSlot = ringPool.slots[index]
            guard index < rings.count else {
                poolSlot.entity.isEnabled = false
                continue
            }
            let ring = rings[index]
            poolSlot.entity.isEnabled = true

            if ringSlots[index].appliedID != ring.id {
                ringSlots[index].appliedID = ring.id
                ringSlots[index].appliedPasses = -1
                ringSlots[index].appliedAimText = ""
                ringSlots[index].tube.name = ring.id.uuidString
            }
            let aimText = Self.aimText(for: ring, in: model)
            if ringSlots[index].appliedAimText != aimText,
               ringSlots[index].aimLabel.setText(aimText, color: DesignTokens.Palette.targetUI) {
                ringSlots[index].appliedAimText = aimText
            }
            poolSlot.entity.position = SIMD3<Float>(ring.position)
            ringSlots[index].tube.position = .zero

            // A brief green flash when a ball passes through. No number:
            // the hoop is a target, not a scoreboard.
            if ringSlots[index].appliedPasses != ring.passes {
                if ringSlots[index].appliedPasses >= 0 {
                    ringSlots[index].flashUntil = now + 0.45
                }
                ringSlots[index].appliedPasses = ring.passes
            }
            let flashing = now < ringSlots[index].flashUntil
            if ringSlots[index].appliedFlashing != flashing {
                ringSlots[index].appliedFlashing = flashing
                ringSlots[index].tube.model?.materials =
                    [flashing ? ringFlashMaterial : ringMaterial]
            }
        }
    }

    // MARK: Helpers

    private static func setAccessibility(on entity: Entity, label: String) {
        SpatialActions.describe(entity, label: label)
    }
}
