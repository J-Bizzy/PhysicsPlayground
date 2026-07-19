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
//  aim input actually changes; hoop score text only when a score lands.
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
    }
    private let ringPool: EntityPool<ModelEntity>
    private var ringSlots: [RingSlot] = []
    private let ringMaterial: UnlitMaterial
    private let ringFlashMaterial: UnlitMaterial

    private let renderLoop = RenderLoop()
    private var model: KinematicsModel?

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
        // Launcher: grabbable base sphere, barrel, aim bead — siblings at
        // room coordinates so manipulation never fights a parent transform.
        let launcherMaterial = SimpleMaterial(
            color: DesignTokens.Palette.launcherUI, roughness: 0.4, isMetallic: true)
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
            materials: [UnlitMaterial(color: DesignTokens.Palette.projectileUI)]
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

        // Strobe dots.
        var dotMaterial = UnlitMaterial(color: DesignTokens.Palette.projectileUI)
        dotMaterial.blending = .transparent(opacity: 0.7)
        let dotMesh = MeshResource.generateSphere(radius: 0.008)
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
        ringMaterial = UnlitMaterial(color: DesignTokens.Palette.targetUI)
        var flash = UnlitMaterial(color: .systemGreen)
        flash.blending = .transparent(opacity: 0.95)
        ringFlashMaterial = flash

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
    }

    // MARK: Render loop

    func startObserving(_ model: KinematicsModel) {
        self.model = model
        renderLoop.start { [weak self, weak model] in
            guard let self, let model else { return }
            self.render(model)
        }
    }

    private func render(_ model: KinematicsModel) {
        // Reading the nonce arms re-rendering for the hoop flash fade.
        _ = model.ringFlashNonce

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
            let points = model.prediction.points.map { SIMD3<Float>($0) }
            if let mesh = TubeMesh.tube(lines: [points], radius: 0.004) {
                arcEntity.model = ModelComponent(mesh: mesh, materials: [arcMaterial])
            } else {
                arcEntity.model = nil
            }
            lastArcInputs = arcInputs
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
            ringSlots[index].tube.model?.materials = [flashing ? ringFlashMaterial : ringMaterial]
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
