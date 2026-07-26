//
//  KinematicsRenderer.swift
//  Physics Playground — Kinematics module
//
//  Renders room-scale projectile motion at 1:1 — physics space IS the
//  room. The free-floating launcher (grab its body to move it, pinch the
//  bead to aim), the predicted arc, pooled balls with strobe-dot trails
//  and floor shadows (the depth cue that makes mid-air height readable),
//  and scoreable hoops with floating counters.
//
//  Frame-rate contract: pools are built once (EntityPool); per-frame work
//  is transform writes only. The predicted-arc tube rebuilds only when an
//  aim input actually changes — and its vertex math runs on a
//  GeometryPipeline worker, so aiming never costs the main thread more
//  than a mesh upload. Hoop score text rebuilds only when a score lands;
//  hoop materials are written only when the flash state flips. Ticked
//  per frame from SceneEvents.Update (observation loops starve during
//  grabs — house rule since the EM module's device findings).
//
//  Grabbable entities are pooled, so each slot's NAME is reassigned to
//  the flight/ring it currently shows — manipulation events map back to
//  model objects by that name. While the hand owns an entity, the render
//  loop must not write its transform (the isManipulating* fields below).
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
    /// Root of everything we render, added to RealityView content at identity.
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    static let launcherName = "launcher"
    static let aimBeadName = "aimBead"

    // Manipulation ownership — set by the space view's router callbacks.
    var isManipulatingLauncher = false
    var isManipulatingBead = false
    var manipulatingBallID: UUID?
    var manipulatingRingID: UUID?

    private static let barrelLength = Float(KinematicsModel.barrelLength)
    static let beadDistance: Float = 0.42
    private static let baseBallRadius: Float = 0.05
    private static let baseShadowRadius: Float = 0.05

    private let launcherBase: ModelEntity
    private let barrel: ModelEntity
    private let bead: ModelEntity
    private let arcEntity = ModelEntity()
    private let arcMaterial: UnlitMaterial

    private let ballPool: EntityPool<ModelEntity>
    private var ballMaterialKeys: [String] = []
    private var appliedTextureVersion = -1
    private let audioEmitter = Entity()
    private var lastSoundID = 0
    private let dotPool: EntityPool<Void>
    private let shadowPool: EntityPool<Void>

    private struct RingSlot {
        let tube: ModelEntity
        let scoreText: Entity
        var appliedID: UUID?
        var appliedScore = -1
        var flashUntil = 0.0
        var appliedFlashing = false
    }
    private let ringPool: EntityPool<ModelEntity>
    private var ringSlots: [RingSlot] = []
    private let ringMaterial: PhysicallyBasedMaterial
    private let ringFlashMaterial: PhysicallyBasedMaterial

    private var arcPipeline: GeometryPipeline<[SIMD3<Float>], TubeBuffers>?

    // Spatial flight numbers: the pod's headline stats living IN the
    // room — peak height floats at the arc's apex (with a drop line
    // showing what the number measures), range + flight time sit on the
    // predicted landing ring, and a protractor at the launcher shows
    // the elevation where the aiming happens. All change-gated with the
    // arc; text meshes cached per rendered string.
    private let apexMarker = Entity()
    private var apexText: ModelEntity!
    private var apexDropLine: ModelEntity!
    private let landingMarker = Entity()
    private var landingText: ModelEntity!
    private let protractorRoot = Entity()
    private var protractorNeedleHolder: Entity!
    private var protractorTextPivot: Entity!
    private var protractorText: ModelEntity!
    private var annotationMeshCache: [String: MeshResource] = [:]
    private let annotationMaterial = UnlitMaterial(color: UIColor(white: 1, alpha: 0.92))

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

    init() {
        root.addChild(Lighting.keyLight())
        // Launcher: grabbable base sphere, barrel, aim bead — siblings at
        // room coordinates so manipulation never fights a parent transform.
        let launcherMaterial = Materials.energized(
            DesignTokens.Palette.launcherUI, roughness: 0.15, metallic: 1.0, glow: 0.0)
        launcherBase = ModelEntity(
            mesh: .generateSphere(radius: 0.05), materials: [launcherMaterial])
        launcherBase.name = Self.launcherName
        Grabbable.configureTouchTarget(launcherBase, collisionRadius: 0.09)
        Self.setAccessibility(on: launcherBase, label: "Launcher. Drag to move it anywhere in the room.")
        root.addChild(launcherBase)

        barrel = ModelEntity(
            mesh: .generateCylinder(height: Self.barrelLength, radius: 0.02),
            materials: [launcherMaterial]
        )
        if let loaded = try? Entity.load(named: "LauncherBarrel") {
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
            mesh: .generateSphere(radius: 0.035),
            materials: [Materials.energized(DesignTokens.Palette.projectileUI, glow: 0.4)]
        )
        bead.name = Self.aimBeadName
        Grabbable.configureTouchTarget(bead, collisionRadius: 0.06)
        Self.setAccessibility(on: bead, label: "Aim bead. Drag to point the launcher.")
        root.addChild(bead)

        // Predicted arc.
        var arcMaterial = UnlitMaterial(color: DesignTokens.Palette.predictedArcUI)
        arcMaterial.blending = .transparent(opacity: 0.5)
        self.arcMaterial = arcMaterial
        root.addChild(arcEntity)

        // Balls: unit sphere scaled per projectile, grabbable for throwing.
        let ballMesh = MeshResource.generateSphere(radius: Self.baseBallRadius)
        ballPool = EntityPool(budget: KinematicsModel.flightBudget) { container in
            let sphere = ModelEntity(
                mesh: ballMesh,
                materials: [SimpleMaterial(color: DesignTokens.Palette.projectileUI,
                                           roughness: 0.5, isMetallic: false)]
            )
            Grabbable.configureTouchTarget(sphere, collisionRadius: Self.baseBallRadius * 1.6)
            Self.setAccessibility(on: sphere, label: "Ball. Grab and throw it.")
            container.addChild(sphere)
            return sphere
        }
        ballMaterialKeys = Array(repeating: "", count: ballPool.budget)
        root.addChild(ballPool.root)

        // Strobe dots — the module's best idea, finally at a size that
        // shows it.
        //
        // Dots dropped at EQUAL TIME intervals are the whole of
        // projectile motion in one picture: their horizontal spacing is
        // constant (nothing accelerates sideways) while their vertical
        // spacing shrinks to nothing at the apex and grows again on the
        // way down. That decomposition is legible only if you can see
        // the dots — at 8 mm and 70% opacity they were a faint dotted
        // line. Bright, opaque, and half again as large, they read as
        // the strobe photograph they are imitating.
        let dotMaterial = Materials.energized(
            DesignTokens.Palette.projectileUI, roughness: 0.3, glow: 0.7)
        let dotMesh = MeshResource.generateSphere(radius: 0.013)
        dotPool = EntityPool(
            budget: KinematicsModel.flightBudget * KinematicsModel.dotsPerFlight
        ) { container in
            container.addChild(ModelEntity(mesh: dotMesh, materials: [dotMaterial]))
        }
        root.addChild(dotPool.root)

        // Floor shadows: flat discs under airborne balls — the depth cue
        // that makes height over the real floor readable.
        var shadowMaterial = UnlitMaterial(color: .black)
        shadowMaterial.blending = .transparent(opacity: 0.22)
        let shadowMesh = MeshResource.generateCylinder(height: 0.002, radius: Self.baseShadowRadius)
        shadowPool = EntityPool(budget: KinematicsModel.flightBudget) { container in
            container.addChild(ModelEntity(mesh: shadowMesh, materials: [shadowMaterial]))
        }
        root.addChild(shadowPool.root)

        // Hoops: torus via TubeMesh circle, score text floating above.
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
                mesh: ringMesh ?? MeshResource.generateSphere(radius: 0.05),
                materials: [capturedRingMaterial]
            )
            Grabbable.configureTouchTarget(tube, collisionRadius: 0.2)
            Self.setAccessibility(on: tube, label: "Hoop. Drag to place it; balls passing down through it score.")
            container.addChild(tube)
            return tube
        }
        for slot in ringPool.slots {
            let text = Entity()
            text.position = [0, 0.3, 0]
            text.components.set(BillboardComponent())
            slot.entity.addChild(text)
            ringSlots.append(RingSlot(tube: slot.payload, scoreText: text))
        }
        root.addChild(ringPool.root)

        audioEmitter.components.set(SpatialAudioComponent())
        root.addChild(audioEmitter)
        BallTextures.warmUp()

        arcPipeline = GeometryPipeline(
            compute: { points in TubeMesh.buffers(lines: [points], radius: 0.004) },
            apply: { [weak self] in self?.applyArc($0) }
        )

        buildFlightAnnotations()
    }

    // MARK: Spatial flight numbers

    private func buildFlightAnnotations() {
        // Apex: a dot on the arc's crest, the height beside it, and a
        // faint plumb line to the floor — the number drawn as geometry.
        let apexDot = ModelEntity(
            mesh: .generateSphere(radius: 0.009),
            materials: [UnlitMaterial(color: DesignTokens.Palette.predictedArcUI)])
        apexMarker.addChild(apexDot)
        let apexPivot = Entity()
        apexPivot.components.set(BillboardComponent())
        apexPivot.position = [0, 0.055, 0]
        apexText = ModelEntity()
        apexPivot.addChild(apexText)
        apexMarker.addChild(apexPivot)
        apexMarker.isEnabled = false
        root.addChild(apexMarker)

        var plumbMaterial = UnlitMaterial(color: .white)
        plumbMaterial.blending = .transparent(opacity: 0.16)
        apexDropLine = ModelEntity(
            mesh: .generateCylinder(height: 1, radius: 0.0012),
            materials: [plumbMaterial])
        apexDropLine.isEnabled = false
        root.addChild(apexDropLine)

        // Landing: a floor ring where the flight will end, wearing the
        // range and flight time.
        let circle: [SIMD3<Float>] = (0...28).map { index in
            let angle = 2 * Float.pi * Float(index) / 28
            return SIMD3(cos(angle), 0, sin(angle)) * 0.07
        }
        var ringMaterial = UnlitMaterial(color: DesignTokens.Palette.predictedArcUI)
        ringMaterial.blending = .transparent(opacity: 0.55)
        if let ringMesh = TubeMesh.tube(lines: [circle], radius: 0.0035, sides: 4) {
            landingMarker.addChild(ModelEntity(mesh: ringMesh, materials: [ringMaterial]))
        }
        let landingPivot = Entity()
        landingPivot.components.set(BillboardComponent())
        landingPivot.position = [0, 0.075, 0]
        landingText = ModelEntity()
        landingPivot.addChild(landingText)
        landingMarker.addChild(landingPivot)
        landingMarker.isEnabled = false
        root.addChild(landingMarker)

        // Protractor: ticks every 15 degrees in the aim's vertical
        // plane, an orange needle at the live elevation, the degree
        // count at its tip. Reads like a real instrument at the muzzle.
        var tickMaterial = UnlitMaterial(color: .white)
        tickMaterial.blending = .transparent(opacity: 0.38)
        let tickMesh = MeshResource.generateBox(size: [0.016, 0.003, 0.003], cornerRadius: 0.001)
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
            mesh: .generateBox(size: [0.055, 0.0045, 0.0045], cornerRadius: 0.002),
            materials: [UnlitMaterial(color: DesignTokens.Palette.projectileUI)])
        needle.position = [0.155, 0, 0]
        protractorNeedleHolder.addChild(needle)
        protractorRoot.addChild(protractorNeedleHolder)
        protractorTextPivot = Entity()
        protractorTextPivot.components.set(BillboardComponent())
        protractorText = ModelEntity()
        protractorTextPivot.addChild(protractorText)
        protractorRoot.addChild(protractorTextPivot)
        root.addChild(protractorRoot)
    }

    private func annotationMesh(_ string: String) -> MeshResource {
        if let cached = annotationMeshCache[string] { return cached }
        if annotationMeshCache.count > 300 { annotationMeshCache.removeAll() }
        let mesh = MeshResource.generateText(
            string, extrusionDepth: 0.002,
            font: .systemFont(ofSize: 0.042, weight: .semibold))
        annotationMeshCache[string] = mesh
        return mesh
    }

    private func setAnnotation(_ entity: ModelEntity, to string: String) {
        let mesh = annotationMesh(string)
        entity.model = ModelComponent(mesh: mesh, materials: [annotationMaterial])
        let bounds = mesh.bounds
        entity.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
    }

    private func updateFlightAnnotations(
        _ model: KinematicsModel, trajectory: ProjectileMotion.Trajectory
    ) {
        // Peak height, where the peak actually is.
        if let apex = trajectory.points.max(by: { $0.y < $1.y }), apex.y > 0.3 {
            apexMarker.isEnabled = true
            apexMarker.position = SIMD3<Float>(apex)
            setAnnotation(apexText, to: String(format: "%.1f m", trajectory.apexHeight))
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
            setAnnotation(landingText, to: String(
                format: "%.1f m · %.1f s", trajectory.range, trajectory.flightTime))
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
        protractorTextPivot.position = [
            Float(cos(elevation)) * 0.235, Float(sin(elevation)) * 0.235, 0]
        setAnnotation(protractorText, to: "\(Int((elevation * 180 / .pi).rounded()))°")
    }

    private func applyArc(_ buffers: TubeBuffers) {
        if let mesh = TubeMesh.mesh(from: buffers) {
            arcEntity.model = ModelComponent(mesh: mesh, materials: [arcMaterial])
        } else {
            arcEntity.model = nil
        }
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
            catchCallout = callout
            root.addChild(callout.root)
        }
        if let caught = model.lastCatch, caught.id != lastCatchID {
            lastCatchID = caught.id
            catchShownAt = CACurrentMediaTime()
            catchCallout?.anchor(at: SIMD3<Float>(caught.position))
            catchCallout?.setText(String(
                format: "Caught\n%.2f m/s   %.2f m\n%.2f s   %.3f J",
                caught.speed, caught.height, caught.flightTime, caught.kineticEnergy))
        }
        // The readout lingers a few seconds, then bows out.
        catchCallout?.isEnabled = CACurrentMediaTime() - catchShownAt < 4.5
    }

    func tick(_ model: KinematicsModel) {
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

        if !isManipulatingLauncher {
            launcherBase.position = launcher
        }
        barrel.orientation = VectorFieldArrows.rotationFromYAxis(to: aim)
        barrel.position = launcher + (Self.barrelLength / 2) * aim
        if !isManipulatingBead {
            bead.position = launcher + Self.beadDistance * aim
        }

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
            updateFlightAnnotations(model, trajectory: trajectory)
        }

        syncFlights(model.flights)
        syncRings(model.rings)
    }

    // MARK: Balls, dots, shadows

    private func syncFlights(_ flights: [KinematicsModel.Flight]) {
        for (index, slot) in ballPool.slots.enumerated() {
            guard index < flights.count else {
                slot.entity.isEnabled = false
                continue
            }
            let flight = flights[index]
            slot.entity.isEnabled = true

            // The slot represents this flight now: rename so manipulation
            // events route to the right model object.
            if slot.payload.name != flight.id.uuidString {
                slot.payload.name = flight.id.uuidString
            }
            applyBallMaterial(for: flight.projectile, at: index, slot: slot)

            let radius = max(Float(flight.projectile.diameter / 2), 0.008)
            slot.entity.scale = SIMD3<Float>(repeating: radius / Self.baseBallRadius)

            if flight.id == manipulatingBallID {
                // Hand owns the sphere; leave both transforms alone.
            } else {
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
        return SimpleMaterial(color: color, roughness: 0.5, isMetallic: false)
    }

    // MARK: Hoops

    private func syncRings(_ rings: [KinematicsModel.Ring]) {
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
                ringSlots[index].appliedScore = -1
                ringSlots[index].tube.name = ring.id.uuidString
            }
            if ring.id != manipulatingRingID {
                poolSlot.entity.position = SIMD3<Float>(ring.position)
                ringSlots[index].tube.position = .zero
            }

            // Score text + a brief green flash when it changes.
            if ringSlots[index].appliedScore != ring.score {
                if ringSlots[index].appliedScore >= 0 {
                    ringSlots[index].flashUntil = now + 0.45
                }
                ringSlots[index].appliedScore = ring.score
                setScoreText(ringSlots[index].scoreText, score: ring.score)
            }
            let flashing = now < ringSlots[index].flashUntil
            if ringSlots[index].appliedFlashing != flashing {
                ringSlots[index].appliedFlashing = flashing
                ringSlots[index].tube.model?.materials =
                    [flashing ? ringFlashMaterial : ringMaterial]
            }
        }
    }

    private func setScoreText(_ entity: Entity, score: Int) {
        entity.children.removeAll()
        guard score > 0 else { return }
        let mesh = MeshResource.generateText(
            "\(score)",
            extrusionDepth: 0.004,
            font: .systemFont(ofSize: 0.12, weight: .bold)
        )
        let text = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: DesignTokens.Palette.targetUI)])
        // generateText's origin is the baseline start; center it.
        let bounds = mesh.bounds
        text.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
        entity.addChild(text)
    }

    // MARK: Helpers

    private static func setAccessibility(on entity: Entity, label: String) {
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: label)
        entity.components.set(accessibility)
    }
}
