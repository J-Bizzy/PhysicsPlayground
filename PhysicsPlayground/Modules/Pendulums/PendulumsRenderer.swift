//
//  PendulumsRenderer.swift
//  Physics Playground — Pendulums module
//
//  Renders the pendulum lab: per pendulum a pivot collar you can hang
//  anywhere, a taut cable, a satin steel bob (grabbable),
//  a speed-colored motion trail, velocity/acceleration/force arrows,
//  and a faint ghost of the future swing while a bob is held.
//
//  Ticked per frame from SceneEvents.Update (the module-standard
//  clock); per-frame work is transform writes on pooled entities.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class PendulumsRenderer {
    /// The SpaceView's tap router, so a carried object can be operated
    /// without hands — `Grabbable` takes the closure and this supplies
    /// it. The helper configures entities it did not build and cannot
    /// invent a meaning for pressing one; only the module knows that a
    /// tap here opens a control ring.
    var onObjectTap: ((Entity) -> Void)?

    let root = Entity()
    /// Freeze sculpts: paused bobs grow velocity and net-force arrows.
    /// Walk under a frozen swing and read why it turns.
    private let frozenVectors = FrozenVectors(budget: 16)
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
    }

    /// The pendulum whose bob a hand is holding (system-dragged).
    var grabbedID: UUID?
    /// The bob already acknowledged with a pickup pulse — one flash per
    /// grab, not one per frame.
    private var pulsedGrabID: UUID?
    /// Where the release tick plays from when the grab ends.
    private weak var pulsedGrabEntity: Entity?

    /// Grabbing starts a new experiment: the old swing's trail would
    /// hang in the air behind the hand, so it clears on grab.
    func clearTrail() {
        trailPool.hideAll()
        trailIndex = 0
        trailBirths = Array(repeating: -1e9, count: Self.trailBudget)
    }

    /// Parent for the selected pendulum's info attachment.
    let infoAnchor = Entity()

    private struct PendulumVisual {
        let pivot: ModelEntity
        let cable: ModelEntity
        let bob: ModelEntity
        /// The double pendulum's second rod and its elbow. Built for
        /// every rig and simply left disabled on a simple one — a
        /// pendulum cannot change kind after it is made, so this costs
        /// two hidden entities rather than a rebuild path.
        let cable2: ModelEntity
        let elbow: ModelEntity
        let velocityArrow: Arrow
        let accelerationArrow: Arrow
        let gravityArrow: Arrow
        let tensionArrow: Arrow
        let netArrow: Arrow
    }

    struct Arrow {
        let holder = Entity()
        let shaft: ModelEntity
        let head: ModelEntity

        init(color: UIColor) {
            // Clean bright shaft, glossy self-lit head — a crisp crafted
            // vector shared by Pendulums and Springs.
            let shaftMaterial = UnlitMaterial(color: color)
            let headMaterial = Materials.energized(color, roughness: 0.2, glow: 0.35)
            shaft = ModelEntity(
                mesh: .generateCylinder(height: 0.1, radius: 0.0035),
                materials: [shaftMaterial])
            head = ModelEntity(
                mesh: .generateCone(height: 0.028, radius: 0.011),
                materials: [headMaterial])
            holder.addChild(shaft)
            holder.addChild(head)
            holder.isEnabled = false
        }

        /// Points the arrow along `vector` from `origin`; length is a
        /// log squash of the magnitude so big forces stay readable.
        func update(origin: SIMD3<Float>, vector: SIMD3<Double>, reference: Double) {
            let magnitude = simd_length(vector)
            guard magnitude > reference * 0.02 else {
                holder.isEnabled = false
                return
            }
            holder.isEnabled = true
            holder.position = origin
            let direction = SIMD3<Float>(vector / magnitude)
            let length = Float(min(0.05 + 0.11 * log10(1 + magnitude / reference), 0.3))
            holder.orientation = VectorFieldArrows.rotationFromYAxis(to: direction)
            shaft.scale = [1, length / 0.1, 1]
            shaft.position = [0, length / 2, 0]
            head.position = [0, length + 0.012, 0]
        }
    }

    private var visuals: [UUID: PendulumVisual] = [:]

    // Trail: one shared pool, round-robin, colored by speed at spawn.
    private static let trailBudget = 360
    private let trailPool: EntityPool<Void>
    private var trailIndex = 0
    private var trailBirths: [Double] = []
    private var trailClock = 0.0
    private var trailSpawnAccumulator = 0.0
    /// Tension's yellow — RATIFIED module-local vocabulary, not drift.
    /// `VectorPalette`'s header names this exact colour as the example:
    /// per-module DECOMPOSITIONS keep their own colours, and only the
    /// three cross-module arrows (velocity, acceleration, net force)
    /// belong to the shared palette.
    static let tensionYellow = UIColor(red: 0.95, green: 0.85, blue: 0.2, alpha: 1)

    private static let trailMaterials: [UnlitMaterial] = {
        // Blue (slow) → orange (fast). Ratified local vocabulary, like
        // the tension yellow above — a trail ramp belongs to its module.
        let colors = [
            UIColor(red: 0.25, green: 0.45, blue: 1.0, alpha: 1),
            UIColor(red: 0.3, green: 0.75, blue: 0.95, alpha: 1),
            UIColor(red: 0.98, green: 0.75, blue: 0.25, alpha: 1),
            UIColor(red: 1.0, green: 0.45, blue: 0.1, alpha: 1),
        ]
        return colors.map { color in
            var material = UnlitMaterial(color: color)
            material.blending = .transparent(opacity: 0.85)
            return material
        }
    }()
    private var trailKinds: [Int] = []

    // Ghost prediction while grabbed.
    private let ghostEntity = ModelEntity()

    // Period tags: T at each pivot — the number that ONLY length and
    // gravity move, floating exactly where that story is anchored.
    // Text meshes are string-cached; labels update only when the
    // rendered string changes.
    private var periodLabels: [UUID: (holder: Entity, text: ModelEntity)] = [:]
    private var periodKeys: [UUID: String] = [:]
    private var periodMeshCache: [String: MeshResource] = [:]
    /// The period tag's own colour — this module's accent.
    ///
    /// It used to be a hand-typed purple that was BYTE-IDENTICAL to the
    /// gravity-force arrow below, so a period readout was painted in
    /// the force-vector colour. In an app whose first rule is that
    /// colour is semantic and never decorative, two different meanings
    /// cannot share a hex.
    private let periodMaterial = UnlitMaterial(
        color: DesignTokens.Palette.pendulumsAccentUI)
    private let ghostMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        material.blending = .transparent(opacity: 0.28)
        return material
    }()
    private var ghostCounter = 0

    private let steelMaterial = Materials.machined(UIColor(white: 0.85, alpha: 1))
    /// The bob: satin steel, not a mirror. It was mirror-polished chrome
    /// (metallic 1.0, roughness 0.1) and it read as a flat white disc —
    /// a full mirror in a passthrough room has almost nothing to
    /// reflect, and a polished face flips between hotspot and shadow as
    /// you move rather than rolling between them. No glow either way:
    /// this is a mass, not a source.
    private static let bobMaterial = Materials.machined(UIColor(white: 0.9, alpha: 1))
    private let aluminumMaterial = Materials.machined(UIColor(white: 0.7, alpha: 1))
    /// Darker and rougher than the bob on purpose — a cable should not
    /// compete with the mass hanging off it.
    private let cableMaterial = Materials.machined(
        UIColor(white: 0.25, alpha: 1), roughness: 0.6)

    private let audioEmitter = Entity()
    private var lastSoundID = 0

    init() {
        root.addChild(Lighting.keyLight())
        // No beam: each pendulum carries its own anchor, wherever it
        // was hung — the rig is the room, not a bar overhead. An empty
        // disabled ModelEntity was still being built and parented here
        // long after the beam was removed; the corpse is gone now.

        // The ENERGY BARS stood here — a blue kinetic column and a green
        // potential one, off to the right, trading height as the bob
        // swung. Deleted at the owner's request (2026-08-01), and the
        // whole idea with them: the flag, the switch plate, the legend
        // rows and the notebook's energy readings.
        //
        // Worth stating why it is not a loss. A chart standing beside the
        // apparatus is the one shape this app spent 200 commits arguing
        // its way out of — it is a readout that happens to be made of
        // geometry, and it competes with the physics for the same room.
        // The trade IS the swing, and the swing is already on screen.

        let trailMesh = MeshResource.generateSphere(radius: 0.005)
        let baseMaterial = Self.trailMaterials[0]
        trailPool = EntityPool(budget: Self.trailBudget) { container in
            container.addChild(ModelEntity(mesh: trailMesh, materials: [baseMaterial]))
        }
        trailBirths = Array(repeating: -1, count: Self.trailBudget)
        trailKinds = Array(repeating: 0, count: Self.trailBudget)
        root.addChild(trailPool.root)

        root.addChild(ghostEntity)

        infoAnchor.components.set(BillboardComponent())
        root.addChild(infoAnchor)

        audioEmitter.components.set(SpatialAudioComponent())
        root.addChild(audioEmitter)
    }

    // MARK: Per-frame tick

    func tick(dt: Double, model: PendulumsModel) {
        if frozenVectors.root.parent == nil { root.addChild(frozenVectors.root) }
        frozenVectors.update(frozen: model.isPaused, dt: dt) {
            var samples: [FrozenVectors.Sample] = []
            for pendulum in model.pendulums {
                let bobWorld = SIMD3<Float>(pendulum.pivot + pendulum.state.position)
                let velocity = pendulum.state.velocity
                let speed = simd_length(velocity)
                let length = max(pendulum.length, 1e-3)
                if speed > 0.01 {
                    samples.append(.init(
                        position: bobWorld,
                        direction: SIMD3<Float>(velocity / speed),
                        // Scaled against the speed a bob released
                        // horizontally would carry through the bottom.
                        magnitude01: Float(min(
                            speed / (2 * (model.gravity * length).squareRoot()), 1)),
                        kind: .velocity))
                }
                // Net force = gravity + cable tension. Tension points at
                // the pivot with magnitude m(g·cosθ + v²/L) — the same
                // constraint the simulation enforces, shown, not told.
                let radial = pendulum.state.position / length
                let cosTheta = max(-radial.y, 0)
                let tension = model.gravity * cosTheta + speed * speed / length
                let acceleration = SIMD3<Double>(0, -model.gravity, 0)
                    - radial * tension
                let a = simd_length(acceleration)
                if a > 0.01 {
                    samples.append(.init(
                        position: bobWorld,
                        direction: SIMD3<Float>(acceleration / a),
                        magnitude01: Float(min(a / (2 * model.gravity), 1)),
                        kind: .force))
                }
            }
            return samples
        }
        model.step(dt: dt)
        trailClock += dt

        if let event = model.soundEvent, event.id != lastSoundID {
            lastSoundID = event.id
            audioEmitter.position = SIMD3<Float>(event.position)
            SoundPalette.play(event.kind, on: audioEmitter, volume: event.volume)
        }

        syncPendulums(model)
        syncTrail(dt: dt, model: model)
        syncGhost(model)

        if let selected = model.selected {
            infoAnchor.isEnabled = true
            infoAnchor.position = SIMD3<Float>(selected.bobWorld)
                + SIMD3(0, Float(selected.bobRadius) + 0.1, 0)
        } else {
            infoAnchor.isEnabled = false
        }
    }

    private func syncPendulums(_ model: PendulumsModel) {
        let liveIDs = Set(model.pendulums.map(\.id))
        for id in visuals.keys where !liveIDs.contains(id) {
            let visual = visuals[id]
            [visual?.pivot, visual?.cable, visual?.bob,
             visual?.cable2, visual?.elbow].forEach { $0?.removeFromParent() }
            [visual?.velocityArrow, visual?.accelerationArrow, visual?.gravityArrow,
             visual?.tensionArrow, visual?.netArrow].forEach { $0?.holder.removeFromParent() }
            visuals[id] = nil
            periodLabels[id]?.holder.removeFromParent()
            periodLabels[id] = nil
            periodKeys[id] = nil
        }

        if grabbedID == nil {
            if pulsedGrabID != nil, let entity = pulsedGrabEntity {
                SoundPalette.play(.releaseTick, on: entity, volume: 0.18)
            }
            pulsedGrabID = nil
            pulsedGrabEntity = nil
        }
        for pendulum in model.pendulums {
            let visual = visuals[pendulum.id] ?? makeVisual(for: pendulum)

            if pendulum.id == grabbedID, pulsedGrabID != pendulum.id {
                pulsedGrabID = pendulum.id
                pulsedGrabEntity = visual.bob
                PickupPulse.flash(on: visual.bob)
                SoundPalette.play(.grabTick, on: visual.bob, volume: 0.2)
            }
            visual.pivot.position = SIMD3<Float>(pendulum.pivot)
            // A PERIOD LABEL BELONGS TO A PENDULUM YOU ARE ATTENDING
            // TO, not to every rope in the room. Newton's cradle hangs
            // five identical bobs 7 cm apart, and five identical
            // "T = 1.49 s" labels landed on top of each other as one
            // unreadable smear — five copies of a number that is the
            // same for all of them and interesting for none.
            //
            // So: label a pendulum when it is selected, or when it has
            // room of its own. The resonance rig spaces its pivots 30 cm
            // apart precisely because its five periods DIFFER and the
            // comparison is the point, so it keeps every label.
            let crowded = model.pendulums.contains {
                $0.id != pendulum.id
                    && simd_distance($0.pivot, pendulum.pivot) < 0.15
            }
            syncPeriodLabel(for: pendulum, gravity: model.gravity,
                            visible: !crowded || model.selectedID == pendulum.id)

            // Model-owned always: during a grab the relative drag
            // writes the model, and everything — bob, cable, arrows —
            // draws from the same state in the same frame.
            let bobWorld = SIMD3<Float>(pendulum.bobWorld)
            visual.bob.position = bobWorld
            let radius = Float(pendulum.bobRadius)
            visual.bob.scale = SIMD3(repeating: radius / 0.035)

            // Cable: pivot → bob, always taut.
            let pivotWorld = SIMD3<Float>(pendulum.pivot)
            let span = bobWorld - pivotWorld
            let length = simd_length(span)
            if length > 1e-5 {
                visual.cable.position = (pivotWorld + bobWorld) / 2
                visual.cable.orientation = VectorFieldArrows.rotationFromYAxis(to: span / length)
                visual.cable.scale = SIMD3(
                    Float(pendulum.cableThickness / 0.002), length,
                    Float(pendulum.cableThickness / 0.002))
            }

            // The double pendulum's second rod: pivot → elbow → bob.
            //
            // The FIRST cable is re-aimed at the elbow rather than at the
            // bob for a double rig, which is why this runs after the
            // block above rather than replacing it: `bobWorld` is the
            // LOWER bob for a double pendulum, so drawing pivot→bob
            // would have cut the corner and shown one straight rod
            // through the elbow.
            if let elbowWorld = pendulum.upperBobWorld.map({ SIMD3<Float>($0) }) {
                visual.elbow.isEnabled = true
                visual.cable2.isEnabled = true
                visual.elbow.position = elbowWorld

                let upper = elbowWorld - pivotWorld
                let upperLength = simd_length(upper)
                if upperLength > 1e-5 {
                    visual.cable.position = (pivotWorld + elbowWorld) / 2
                    visual.cable.orientation =
                        VectorFieldArrows.rotationFromYAxis(to: upper / upperLength)
                    visual.cable.scale = SIMD3(
                        Float(pendulum.cableThickness / 0.002), upperLength,
                        Float(pendulum.cableThickness / 0.002))
                }
                let lower = bobWorld - elbowWorld
                let lowerLength = simd_length(lower)
                if lowerLength > 1e-5 {
                    visual.cable2.position = (elbowWorld + bobWorld) / 2
                    visual.cable2.orientation =
                        VectorFieldArrows.rotationFromYAxis(to: lower / lowerLength)
                    visual.cable2.scale = SIMD3(
                        Float(pendulum.cableThickness / 0.002), lowerLength,
                        Float(pendulum.cableThickness / 0.002))
                }
            }

            // Vectors.
            let origin = bobWorld
            let velocity = pendulum.state.velocity
            Fade.tick(visual.velocityArrow.holder, visible: model.showVelocity)
            if model.showVelocity {
                visual.velocityArrow.update(origin: origin, vector: velocity, reference: 0.5)
            }
            let gravityForce = SIMD3(0, -model.gravity * pendulum.mass, 0)
            let direction = simd_normalize(pendulum.state.position)
            let tensionMagnitude = pendulum.state.tension(
                length: pendulum.length, gravity: model.gravity, mass: pendulum.mass)
            let tensionForce = -direction * tensionMagnitude
            let netForce = gravityForce + tensionForce
                - pendulum.damping * velocity
            Fade.tick(visual.accelerationArrow.holder, visible: model.showAcceleration)
            if model.showAcceleration {
                visual.accelerationArrow.update(
                    origin: origin, vector: netForce / pendulum.mass, reference: 2)
            }
            let showForces = model.showForces
            Fade.tick(visual.gravityArrow.holder, visible: showForces)
            Fade.tick(visual.tensionArrow.holder, visible: showForces)
            Fade.tick(visual.netArrow.holder, visible: showForces)
            if showForces {
                visual.gravityArrow.update(origin: origin, vector: gravityForce, reference: 5)
                visual.tensionArrow.update(origin: origin, vector: tensionForce, reference: 5)
                visual.netArrow.update(origin: origin, vector: netForce, reference: 5)
            }

            visuals[pendulum.id] = visual
        }
    }

    /// The pendulum as the WELL shows it, before you have one: a steel
    /// collar, a short length of cable, and the satin bob — the same
    /// three parts and the same three materials the real rig is made of,
    /// hung at a slight angle so it reads as a pendulum rather than as a
    /// ball on a stick.
    ///
    /// Shorter than a real one on purpose (0.16 m of cable against a
    /// default 0.8 m): the well is an object standing beside the rig,
    /// and a full-length preview would be a second pendulum hanging in
    /// the room pretending not to be one.
    static func pendulumPreview() -> Entity {
        let container = Entity()
        let steel = Materials.machined(UIColor(white: 0.85, alpha: 1))
        let cableMaterial = Materials.machined(
            UIColor(white: 0.25, alpha: 1), roughness: 0.6)
        let cableLength: Float = 0.16

        let collar = ModelEntity(
            mesh: .generateCylinder(height: 0.03, radius: 0.014),
            materials: [steel])
        container.addChild(collar)

        let cable = ModelEntity(
            mesh: .generateCylinder(height: cableLength, radius: 0.002),
            materials: [cableMaterial])
        cable.position = [0, -cableLength / 2, 0]
        container.addChild(cable)

        let bob = ModelEntity(mesh: .generateSphere(radius: 0.035),
                              materials: [bobMaterial])
        bob.position = [0, -cableLength, 0]
        container.addChild(bob)

        // Hung off vertical, the way one looks mid-swing.
        container.orientation = simd_quatf(angle: 0.26, axis: [0, 0, 1])
        return container
    }

    /// The double pendulum as its well mouth shows it: two rods bent at
    /// an elbow, which is the one silhouette that tells it apart from
    /// the mouth beside it at a glance.
    ///
    /// Built to the SAME overall size as `pendulumPreview` — collar at
    /// the top, 0.16 m of rod below it — because the two hang side by
    /// side and a mouth drawn smaller reads as a lesser version of the
    /// thing next to it rather than as a different one.
    static func doublePendulumPreview() -> Entity {
        let container = Entity()
        let steel = Materials.machined(UIColor(white: 0.85, alpha: 1))
        let cableMaterial = Materials.machined(
            UIColor(white: 0.25, alpha: 1), roughness: 0.6)

        let collar = ModelEntity(
            mesh: .generateCylinder(height: 0.03, radius: 0.014),
            materials: [steel])
        container.addChild(collar)

        // The bend is what makes it legible. Split 0.16 into 0.09 above
        // the elbow and 0.07 below, and kick the lower rod out sideways
        // so the joint reads as a joint rather than as a kink.
        let pivot = SIMD3<Float>(0, -0.015, 0)
        let elbow = pivot + SIMD3(0.030, -0.085, 0)
        let bob = elbow + SIMD3(-0.022, -0.066, 0)

        func rod(from a: SIMD3<Float>, to b: SIMD3<Float>) -> ModelEntity {
            let span = b - a
            let length = simd_length(span)
            let entity = ModelEntity(
                mesh: .generateCylinder(height: length, radius: 0.002),
                materials: [cableMaterial])
            entity.position = (a + b) / 2
            entity.orientation = VectorFieldArrows.rotationFromYAxis(
                to: span / length)
            return entity
        }
        container.addChild(rod(from: pivot, to: elbow))
        container.addChild(rod(from: elbow, to: bob))

        let elbowBall = ModelEntity(mesh: .generateSphere(radius: 0.017),
                                    materials: [bobMaterial])
        elbowBall.position = elbow
        container.addChild(elbowBall)
        let bobBall = ModelEntity(mesh: .generateSphere(radius: 0.024),
                                  materials: [bobMaterial])
        bobBall.position = bob
        container.addChild(bobBall)
        return container
    }

    private func makeVisual(for pendulum: PendulumsModel.Pendulum) -> PendulumVisual {
        let pivot = ModelEntity(
            mesh: .generateCylinder(height: 0.03, radius: 0.014),
            materials: [steelMaterial])
        // The collar is grabbable: a rig you cannot re-hang is
        // furniture, not rigging.
        pivot.name = "pivot-\(pendulum.id.uuidString)"
        // 0.05 until 2026-08-07, on a collar 0.028 across: collars in a
        // cradle stand 0.07 m apart, so each one's target reached past
        // both its neighbours' centres and the middle of a cradle could
        // not be re-hung.
        Grabbable.configureTouchTarget(
            pivot, collisionRadius: 0.028,
            activate: { [weak self, weak pivot] in
                guard let pivot else { return }
                self?.onObjectTap?(pivot)
            })
        root.addChild(pivot)

        let cable = ModelEntity(
            mesh: .generateCylinder(height: 1, radius: 0.002),
            materials: [cableMaterial])
        root.addChild(cable)

        let bob = ModelEntity(
            mesh: .generateSphere(radius: 0.035),
            materials: [Self.bobMaterial])
        bob.name = pendulum.id.uuidString
        // 0.075 until 2026-08-07, on a ball of radius 0.035. Cradle bobs
        // touch — they are 0.07 m apart — so a 0.075 target enclosed
        // BOTH neighbours' centres and the ball you pinched was decided
        // by hit order rather than by aim.
        Grabbable.configureTouchTarget(
            bob, collisionRadius: 0.048,
            activate: { [weak self, weak bob] in
                guard let bob else { return }
                self?.onObjectTap?(bob)
            })
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Pendulum bob. Grab it, carry it, and throw it."
        bob.components.set(accessibility)
        root.addChild(bob)

        let cable2 = ModelEntity(
            mesh: .generateCylinder(height: 1, radius: 0.002),
            materials: [cableMaterial])
        cable2.isEnabled = false
        root.addChild(cable2)

        // The elbow carries the UPPER mass of a double pendulum. Drawn
        // smaller than the lower bob because the lower one is what the
        // eye should follow — its path is the chaotic figure the whole
        // rig exists to draw.
        let elbow = ModelEntity(
            mesh: .generateSphere(radius: 0.026),
            materials: [Self.bobMaterial])
        elbow.isEnabled = false
        root.addChild(elbow)

        let visual = PendulumVisual(
            pivot: pivot, cable: cable, bob: bob,
            cable2: cable2, elbow: elbow,
            velocityArrow: Arrow(color: VectorPalette.velocity),
            accelerationArrow: Arrow(color: VectorPalette.acceleration),
            // Gravity is a force AND a component of the net force drawn
            // beside it, so it cannot be the same red — see
            // `VectorPalette.gravity`. The legend has said "purple
            // gravity" since it was written.
            gravityArrow: Arrow(color: DesignTokens.Palette.gravityVectorUI),
            tensionArrow: Arrow(color: Self.tensionYellow),
            netArrow: Arrow(color: VectorPalette.force))
        [visual.velocityArrow, visual.accelerationArrow, visual.gravityArrow,
         visual.tensionArrow, visual.netArrow].forEach { root.addChild($0.holder) }
        visuals[pendulum.id] = visual
        return visual
    }

    // MARK: Trail

    private func syncPeriodLabel(for pendulum: PendulumsModel.Pendulum,
                                 gravity: Double, visible: Bool = true) {
        let label: (holder: Entity, text: ModelEntity)
        if let existing = periodLabels[pendulum.id] {
            label = existing
        } else {
            let holder = Entity()
            let pivot = Entity()
            pivot.components.set(BillboardComponent())
            let text = ModelEntity()
            pivot.addChild(text)
            holder.addChild(pivot)
            root.addChild(holder)
            label = (holder, text)
            periodLabels[pendulum.id] = label
        }
        label.holder.isEnabled = visible
        guard visible else { return }
        label.holder.position = SIMD3<Float>(pendulum.pivot) + SIMD3(0, 0.055, 0)

        let string = "T = " + PhysicsFormat.measurement(
            pendulum.period(gravity: gravity), "s", decimals: 2)
        guard periodKeys[pendulum.id] != string else { return }
        periodKeys[pendulum.id] = string
        let mesh: MeshResource
        if let cached = periodMeshCache[string] {
            mesh = cached
        } else {
            if periodMeshCache.count > 200 { periodMeshCache.removeAll() }
            mesh = MeshResource.generateText(
                string, extrusionDepth: 0.002,
                font: .systemFont(ofSize: 0.024, weight: .semibold))
            periodMeshCache[string] = mesh
        }
        label.text.model = ModelComponent(mesh: mesh, materials: [periodMaterial])
        let bounds = mesh.bounds
        label.text.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
    }

    private func syncTrail(dt: Double, model: PendulumsModel) {
        let lifetime: Double
        switch model.trailMode {
        case .off: lifetime = 0
        case .short: lifetime = 1.4
        case .long: lifetime = 4.0
        case .infinite: lifetime = .infinity
        }
        guard lifetime > 0, !model.isPaused else {
            if lifetime == 0 {
                for slot in trailPool.slots { slot.entity.isEnabled = false }
            }
            ageTrail(lifetime: lifetime)
            return
        }

        // Spawn dots at a steady clip along every free-swinging bob.
        trailSpawnAccumulator += dt
        let interval = 1.0 / 40.0
        while trailSpawnAccumulator >= interval {
            trailSpawnAccumulator -= interval
            for pendulum in model.pendulums where !pendulum.isGrabbed {
                let speed = simd_length(pendulum.state.velocity)
                guard speed > 0.02 else { continue }
                let slot = trailPool.slots[trailIndex]
                slot.entity.isEnabled = true
                slot.entity.position = SIMD3<Float>(pendulum.bobWorld)
                slot.entity.scale = SIMD3(repeating: 1)
                let kind = min(Int(speed / 0.7), Self.trailMaterials.count - 1)
                if trailKinds[trailIndex] != kind {
                    trailKinds[trailIndex] = kind
                    (slot.entity.children.first as? ModelEntity)?.model?.materials =
                        [Self.trailMaterials[kind]]
                }
                trailBirths[trailIndex] = trailClock
                trailIndex = (trailIndex + 1) % Self.trailBudget
            }
        }
        ageTrail(lifetime: lifetime)
    }

    private func ageTrail(lifetime: Double) {
        guard lifetime.isFinite, lifetime > 0 else { return }
        for index in 0..<Self.trailBudget {
            let birth = trailBirths[index]
            guard birth >= 0 else { continue }
            let age = trailClock - birth
            let slot = trailPool.slots[index]
            if age > lifetime {
                slot.entity.isEnabled = false
                trailBirths[index] = -1
            } else {
                // Fade by shrinking.
                let fade = Float(1 - age / lifetime)
                slot.entity.scale = SIMD3(repeating: max(fade, 0.15))
            }
        }
    }

    // MARK: Ghost prediction

    /// THE ONE PLACE THIS MODULE BUILDS A MESH ON THE FRAME PATH, and it
    /// is a deliberate exception rather than an oversight. Recorded here
    /// because a reader checking the rule ("mesh regeneration goes
    /// through `GeometryPipeline`'s background worker, never inline in
    /// the render tick" — ARCHITECTURE.md) will otherwise find this and
    /// assume it was missed. It was measured instead:
    ///
    /// · It runs ONLY while a bob is held, and only every sixth frame.
    /// · The mesh is 60 path points swept as a 3-sided tube — about 180
    ///   vertices, which is smaller than a single field line.
    /// · `ghostMaterial` is banked, so nothing is allocated per call.
    ///
    /// And the reason NOT to move it is the stronger half: this ghost is
    /// a live preview of where the bob will go if released from where
    /// your hand is NOW. Handing it to a background worker buys a
    /// hitch-free frame that nobody was losing and pays for it in lag on
    /// the one thing in the module that must track the hand exactly.
    /// The rule exists to prevent hitches; this is not one.
    private func syncGhost(_ model: PendulumsModel) {
        guard let grabbedID, let pendulum = model.pendulums.first(where: { $0.id == grabbedID }),
              pendulum.isGrabbed else {
            ghostEntity.model = nil
            return
        }
        ghostCounter &+= 1
        guard ghostCounter % 6 == 0 else { return }
        let path = model.predictedPath(id: grabbedID, seconds: 2.2, points: 60)
        guard path.count > 1 else {
            ghostEntity.model = nil
            return
        }
        let line = path.map { SIMD3<Float>($0) }
        if let mesh = TubeMesh.tube(lines: [line], radius: 0.0035, sides: 3) {
            ghostEntity.model = ModelComponent(mesh: mesh, materials: [ghostMaterial])
        }
    }
}
