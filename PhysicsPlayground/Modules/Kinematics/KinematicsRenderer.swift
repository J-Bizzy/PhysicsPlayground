//
//  KinematicsRenderer.swift
//  Physics Playground — Kinematics module
//
//  Renders room-scale projectile motion at 1:1 — physics space is the
//  room: the free-floating launcher, the predicted arc, pooled balls
//  with strobe-dot trails and floor shadows, and hoops that light when a ball passes. Pools
//  are built once and the per-frame work is transform writes; the arc
//  tube rebuilds only when an aim input changes, on a GeometryPipeline
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

    // Spatial flight numbers: peak height at the apex with a drop line,
    // range and flight time on the landing ring, a protractor at the
    // launcher. Change-gated with the arc.
    private let apexMarker = Entity()
    private var apexLabel: BackedLabel!
    private var apexDropLine: ModelEntity!
    private let landingMarker = Entity()
    private var landingLabel: BackedLabel!
    private let protractorRoot = Entity()
    private var protractorNeedleHolder: Entity!
    private var protractorTextPivot: Entity!
    private var protractorLabel: BackedLabel!
    /// The speed, beside the bead that sets it.
    private let speedTextPivot = Entity()
    private var speedLabel: BackedLabel!
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
            mesh: Primitives.sphere(radius: 0.035),
            materials: [Materials.energized(DesignTokens.Palette.projectileUI, glow: 0.4)]
        )
        bead.name = Self.aimBeadName
        Grabbable.configureTouchTarget(
            bead, collisionRadius: 0.048,
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
        root.addChild(arcCasingEntity)
        root.addChild(arcEntity)
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
        // shrinking to nothing at the apex. Bright and opaque, so they read as
        // the strobe photograph they imitate.
        let dotMaterial = Materials.energized(
            DesignTokens.Palette.projectileUI, roughness: 0.3, glow: 0.7)
        let dotMesh = Primitives.sphere(radius: 0.013)
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

        // Protractor: ticks every 15 degrees in the aim's vertical
        // plane, an orange needle at the live elevation, the degree
        // count at its tip. Reads like a real instrument at the muzzle.
        let tickMaterial = Materials.unlit(.white, opacity: 0.38)
        let tickMesh = Primitives.box(size: [0.016, 0.003, 0.003], cornerRadius: 0.001)
        for degrees in stride(from: -75, through: 75, by: 15) {
            let holder = Entity()
            holder.orientation = simd_quatf(
                angle: Float(degrees) * .pi / 180, axis: [0, 0, 1])
            let tick = ModelEntity(mesh: tickMesh, materials: [tickMaterial])
            tick.position = [0.165, 0, 0]
            holder.addChild(tick)
            protractorRoot.addChild(holder)
        }
        protractorNeedleHolder = Entity()
        let needle = ModelEntity(
            mesh: Primitives.box(size: [0.055, 0.0045, 0.0045], cornerRadius: 0.002),
            materials: [UnlitMaterial(color: DesignTokens.Palette.projectileUI)])
        needle.position = [0.155, 0, 0]
        protractorNeedleHolder.addChild(needle)
        protractorRoot.addChild(protractorNeedleHolder)
        protractorTextPivot = Entity()
        protractorTextPivot.components.set(BillboardComponent())
        protractorLabel = BackedLabel(size: 0.042)
        protractorTextPivot.addChild(protractorLabel.root)
        protractorRoot.addChild(protractorTextPivot)
        root.addChild(protractorRoot)
        speedTextPivot.components.set(BillboardComponent())
        speedLabel = BackedLabel(size: 0.036)
        speedTextPivot.addChild(speedLabel.root)
        root.addChild(speedTextPivot)
    }

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
            apexMarker.isEnabled = true
            apexMarker.position = SIMD3<Float>(apex)
            shown = apexLabel.setText(
                PhysicsFormat.measurement(trajectory.apexHeight, "m", decimals: 1),
                color: Self.annotationWhite) && shown
            apexDropLine.isEnabled = true
            apexDropLine.position = SIMD3(Float(apex.x), Float(apex.y) / 2, Float(apex.z))
            apexDropLine.scale = SIMD3(1, Float(apex.y), 1)
        } else {
            apexMarker.isEnabled = false
            apexDropLine.isEnabled = false
        }

        // Range and flight time, at the landing spot.
        if trajectory.landed, let landing = trajectory.landingPoint {
            landingMarker.isEnabled = true
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
            landingMarker.isEnabled = false
        }

        // The protractor rides the launcher, yawed into the aim plane.
        let aim = model.aimDirection
        protractorRoot.position = SIMD3<Float>(model.launcherPosition)
        let azimuth = atan2(aim.z, aim.x)
        protractorRoot.orientation = simd_quatf(angle: -Float(azimuth), axis: [0, 1, 0])
        let elevation = asin(max(-1, min(1, aim.y)))
        protractorNeedleHolder.orientation = simd_quatf(
            angle: Float(elevation), axis: [0, 0, 1])
        // On the aim line the barrel hid it; lifted off it on the side the
        // arc never bends toward, it reads from where you stand.
        protractorTextPivot.position = [
            Float(cos(elevation)) * 0.235 - Float(sin(elevation)) * 0.055,
            Float(sin(elevation)) * 0.235 + Float(cos(elevation)) * 0.055, 0]
        shown = protractorLabel.setText(
            PhysicsFormat.angle(elevation * 180 / .pi, decimals: 0),
            color: Self.annotationWhite) && shown

        // The speed, beside the bead that sets it, on the side of the aim
        // line the arc never bends toward (gravity takes it below).
        let aimF = SIMD3<Float>(aim)
        let lift = simd_normalize(SIMD3<Float>(0, 1, 0) - aimF * aimF.y)
        speedTextPivot.position = SIMD3<Float>(model.launcherPosition)
            + Self.beadDistance(forSpeed: model.launchSpeed) * aimF + 0.09 * lift
        shown = speedLabel.setText(
            PhysicsFormat.measurement(model.launchSpeed, "m/s", decimals: 1),
            color: Self.annotationWhite) && shown
        return shown
    }

    /// Both passes of the arc, built off-thread together so the casing
    /// can never lag a frame behind the line it underwrites.
    private nonisolated struct ArcTube: Sendable {
        var core = TubeBuffers()
        var casing = TubeBuffers()
    }

    private func applyArc(_ tube: ArcTube) {
        if let mesh = TubeMesh.mesh(from: tube.core) {
            arcEntity.model = ModelComponent(mesh: mesh, materials: [arcMaterial])
        } else {
            arcEntity.model = nil
        }
        if let casingMesh = TubeMesh.mesh(from: tube.casing) {
            arcCasingEntity.model = ModelComponent(mesh: casingMesh,
                                                   materials: [arcCasingMaterial])
        } else {
            arcCasingEntity.model = nil
        }
    }

    private func applyGhost(_ tube: ArcTube) {
        if let mesh = TubeMesh.mesh(from: tube.core) {
            ghostEntity.model = ModelComponent(mesh: mesh, materials: [ghostMaterial])
        } else {
            ghostEntity.model = nil
        }
        if let casingMesh = TubeMesh.mesh(from: tube.casing) {
            ghostCasingEntity.model = ModelComponent(mesh: casingMesh,
                                                     materials: [arcCasingMaterial])
        } else {
            ghostCasingEntity.model = nil
        }
    }

    private func applyRecordedPaths(_ tube: ArcTube) {
        if let mesh = TubeMesh.mesh(from: tube.core) {
            pathEntity.model = ModelComponent(mesh: mesh, materials: [pathMaterial])
        } else {
            pathEntity.model = nil
        }
        if let casingMesh = TubeMesh.mesh(from: tube.casing) {
            pathCasingEntity.model = ModelComponent(mesh: casingMesh,
                                                    materials: [pathCasingMaterial])
        } else {
            pathCasingEntity.model = nil
        }
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
        // The readout lingers a few seconds, then bows out.
        catchCallout?.isEnabled = CACurrentMediaTime() - catchShownAt < 4.5
    }

    func tick(_ model: KinematicsModel) {
        tickFlightCallout(model)
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

        // Predicted arc — rebuild only when an input actually changed.
        let arcInputs = ArcInputs(
            aim: model.aimDirection, speed: model.launchSpeed,
            launcher: model.launcherPosition, gravity: model.gravity,
            air: model.airResistance, windSpeed: model.windSpeed,
            windDirection: model.windDirectionDegrees, projectile: model.projectile
        )
        if arcInputs != lastArcInputs {
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

        // Ghost arcs: the aim solutions for the hoop being aimed at, and
        // the vacuum arc while the air is on. Rebuilt on a change of
        // inputs only — the solve is memoised in the model, the tubes
        // are not free.
        let ghostInputs = GhostInputs(
            arc: arcInputs, target: model.aimTargetID,
            hoop: model.aimTargetID.flatMap { id in
                model.rings.first { $0.id == id }?.position
            })
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
            if let vacuum = model.vacuumPrediction {
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
        let target: Float = flight == nil ? 0 : 1
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

        var dotIndex = 0
        for flight in flights {
            for dot in flight.dots where dotIndex < dotPool.budget {
                let slot = dotPool.slots[dotIndex]
                slot.entity.isEnabled = true
                slot.entity.position = SIMD3<Float>(dot)
                dotIndex += 1
            }
        }
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

    static func ballPreview() -> Entity {
        var material = PhysicallyBasedMaterial()
        if let texture = BallTextures.texture(for: Projectile.basketball.name) {
            material.baseColor = .init(tint: .white, texture: .init(texture))
        } else {
            material.baseColor = .init(tint: DesignTokens.Palette.projectileUI)
        }
        material.roughness = .init(floatLiteral: 0.6)
        // A 3.5 cm token wearing the basketball's skin: beside the hoop's mouth
        // 13 cm away, a full-size ball ran into it.
        return ModelEntity(mesh: Primitives.sphere(radius: 0.035),
                           materials: [material])
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
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: label)
        entity.components.set(accessibility)
    }
}
