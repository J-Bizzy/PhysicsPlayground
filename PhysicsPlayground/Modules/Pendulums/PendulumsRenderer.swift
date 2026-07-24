//
//  PendulumsRenderer.swift
//  Physics Playground — Pendulums module
//
//  Renders the pendulum lab: a brushed-aluminum beam overhead, and per
//  pendulum a pivot collar, taut cable, polished steel bob (grabbable),
//  a speed-colored motion trail, velocity/acceleration/force arrows,
//  floating kinetic/potential energy bars, and a faint ghost of the
//  future swing while a bob is held.
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
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    /// The pendulum whose bob a hand is holding (system-dragged).
    var grabbedID: UUID?

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
            let material = UnlitMaterial(color: color)
            shaft = ModelEntity(
                mesh: .generateCylinder(height: 0.1, radius: 0.0028),
                materials: [material])
            head = ModelEntity(
                mesh: .generateCone(height: 0.024, radius: 0.008),
                materials: [material])
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
    private let beam: ModelEntity

    // Energy bars: kinetic (blue) and potential (green), floating
    // beside the beam's right end.
    private let kineticBar: ModelEntity
    private let potentialBar: ModelEntity
    private let energyBarsRoot = Entity()
    private static let barsBase = SIMD3<Float>(1.25, 1.45, -1.1)
    private static let barFullHeight: Float = 0.5

    // Trail: one shared pool, round-robin, colored by speed at spawn.
    private static let trailBudget = 360
    private let trailPool: EntityPool<Void>
    private var trailIndex = 0
    private var trailBirths: [Double] = []
    private var trailClock = 0.0
    private var trailSpawnAccumulator = 0.0
    private static let trailMaterials: [UnlitMaterial] = {
        // Blue (slow) → orange (fast).
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
    private let periodMaterial = UnlitMaterial(color: UIColor(
        red: 0.55, green: 0.35, blue: 0.95, alpha: 1))
    private let ghostMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        material.blending = .transparent(opacity: 0.28)
        return material
    }()
    private var ghostCounter = 0

    private let steelMaterial = SimpleMaterial(
        color: UIColor(white: 0.85, alpha: 1), roughness: 0.15, isMetallic: true)
    /// The bob: mirror-polished chrome — clear-coat gloss over metal, no
    /// glow (it's a mass, not a source).
    private static let bobMaterial = Materials.energized(
        UIColor(white: 0.9, alpha: 1), roughness: 0.1, metallic: 1.0, glow: 0.0)
    private let aluminumMaterial = Materials.energized(
        UIColor(white: 0.7, alpha: 1), roughness: 0.3, metallic: 1.0, glow: 0.0)
    private let cableMaterial = SimpleMaterial(
        color: UIColor(white: 0.25, alpha: 1), roughness: 0.6, isMetallic: true)

    private let audioEmitter = Entity()
    private var lastSoundID = 0

    init() {
        root.addChild(Lighting.keyLight())
        // The machined beam overhead.
        beam = ModelEntity(
            mesh: .generateBox(
                size: [Float(2 * PendulumsModel.beamHalfLength + 0.25), 0.045, 0.07],
                cornerRadius: 0.008),
            materials: [aluminumMaterial])
        beam.position = SIMD3<Float>(PendulumsModel.beamCenter)
        root.addChild(beam)

        var kineticMaterial = UnlitMaterial(color: UIColor(red: 0.25, green: 0.5, blue: 1.0, alpha: 1))
        kineticMaterial.blending = .transparent(opacity: 0.85)
        var potentialMaterial = UnlitMaterial(color: UIColor(red: 0.2, green: 0.8, blue: 0.35, alpha: 1))
        potentialMaterial.blending = .transparent(opacity: 0.85)
        kineticBar = ModelEntity(
            mesh: .generateBox(size: [0.05, 1, 0.05], cornerRadius: 0.01),
            materials: [kineticMaterial])
        potentialBar = ModelEntity(
            mesh: .generateBox(size: [0.05, 1, 0.05], cornerRadius: 0.01),
            materials: [potentialMaterial])
        energyBarsRoot.position = Self.barsBase
        kineticBar.position = [0, 0, 0]
        potentialBar.position = [0.09, 0, 0]
        energyBarsRoot.addChild(kineticBar)
        energyBarsRoot.addChild(potentialBar)
        root.addChild(energyBarsRoot)

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
        model.step(dt: dt)
        trailClock += dt

        if let event = model.soundEvent, event.id != lastSoundID {
            lastSoundID = event.id
            audioEmitter.position = SIMD3<Float>(event.position)
            SoundPalette.play(event.kind, on: audioEmitter, volume: event.volume)
        }

        syncPendulums(model)
        syncTrail(dt: dt, model: model)
        syncEnergyBars(model)
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
            [visual?.pivot, visual?.cable, visual?.bob].forEach { $0?.removeFromParent() }
            [visual?.velocityArrow, visual?.accelerationArrow, visual?.gravityArrow,
             visual?.tensionArrow, visual?.netArrow].forEach { $0?.holder.removeFromParent() }
            visuals[id] = nil
            periodLabels[id]?.holder.removeFromParent()
            periodLabels[id] = nil
            periodKeys[id] = nil
        }

        for pendulum in model.pendulums {
            let visual = visuals[pendulum.id] ?? makeVisual(for: pendulum)

            visual.pivot.position = SIMD3<Float>(pendulum.pivot)
            syncPeriodLabel(for: pendulum, gravity: model.gravity)

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

            // Vectors.
            let origin = bobWorld
            let velocity = pendulum.state.velocity
            visual.velocityArrow.holder.isEnabled = model.showVelocity
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
            visual.accelerationArrow.holder.isEnabled = model.showAcceleration
            if model.showAcceleration {
                visual.accelerationArrow.update(
                    origin: origin, vector: netForce / pendulum.mass, reference: 2)
            }
            let showForces = model.showForces
            visual.gravityArrow.holder.isEnabled = showForces
            visual.tensionArrow.holder.isEnabled = showForces
            visual.netArrow.holder.isEnabled = showForces
            if showForces {
                visual.gravityArrow.update(origin: origin, vector: gravityForce, reference: 5)
                visual.tensionArrow.update(origin: origin, vector: tensionForce, reference: 5)
                visual.netArrow.update(origin: origin, vector: netForce, reference: 5)
            }

            visuals[pendulum.id] = visual
        }
    }

    private func makeVisual(for pendulum: PendulumsModel.Pendulum) -> PendulumVisual {
        let pivot = ModelEntity(
            mesh: .generateCylinder(height: 0.03, radius: 0.014),
            materials: [steelMaterial])
        root.addChild(pivot)

        let cable = ModelEntity(
            mesh: .generateCylinder(height: 1, radius: 0.002),
            materials: [cableMaterial])
        root.addChild(cable)

        let bob = ModelEntity(
            mesh: .generateSphere(radius: 0.035),
            materials: [Self.bobMaterial])
        bob.name = pendulum.id.uuidString
        Grabbable.configureTouchTarget(bob, collisionRadius: 0.075)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Pendulum bob. Grab it, carry it, and throw it."
        bob.components.set(accessibility)
        root.addChild(bob)

        let visual = PendulumVisual(
            pivot: pivot, cable: cable, bob: bob,
            velocityArrow: Arrow(color: UIColor(red: 0.25, green: 0.55, blue: 1, alpha: 1)),
            accelerationArrow: Arrow(color: UIColor(red: 1, green: 0.55, blue: 0.1, alpha: 1)),
            gravityArrow: Arrow(color: UIColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 1)),
            tensionArrow: Arrow(color: UIColor(red: 0.95, green: 0.85, blue: 0.2, alpha: 1)),
            netArrow: Arrow(color: UIColor(red: 0.95, green: 0.2, blue: 0.25, alpha: 1)))
        [visual.velocityArrow, visual.accelerationArrow, visual.gravityArrow,
         visual.tensionArrow, visual.netArrow].forEach { root.addChild($0.holder) }
        visuals[pendulum.id] = visual
        return visual
    }

    // MARK: Trail

    private func syncPeriodLabel(for pendulum: PendulumsModel.Pendulum, gravity: Double) {
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
        label.holder.position = SIMD3<Float>(pendulum.pivot) + SIMD3(0, 0.055, 0)

        let string = String(format: "T = %.2f s", pendulum.period(gravity: gravity))
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

    // MARK: Energy bars

    private func syncEnergyBars(_ model: PendulumsModel) {
        guard model.showEnergyBars, let pendulum = model.selected else {
            energyBarsRoot.isEnabled = false
            return
        }
        energyBarsRoot.isEnabled = true
        let energies = pendulum.state.energies(
            length: pendulum.length, gravity: model.gravity, mass: pendulum.mass)
        // Normalize both bars against the current total, so the swap
        // between them is the story; the sum is the full bar height.
        let total = max(energies.kinetic + energies.potential, 1e-6)
        let reference = max(total, 0.2)
        let kineticHeight = Float(energies.kinetic / reference) * Self.barFullHeight
        let potentialHeight = Float(energies.potential / reference) * Self.barFullHeight
        kineticBar.scale = [1, max(kineticHeight, 0.004), 1]
        kineticBar.position = [0, max(kineticHeight, 0.004) / 2, 0]
        potentialBar.scale = [1, max(potentialHeight, 0.004), 1]
        potentialBar.position = [0.09, max(potentialHeight, 0.004) / 2, 0]
    }

    // MARK: Ghost prediction

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
