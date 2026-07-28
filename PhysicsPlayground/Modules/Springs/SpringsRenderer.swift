//
//  SpringsRenderer.swift
//  Physics Playground — Springs module
//
//  Renders the spring lab: aluminum supports, a coiled helix spring
//  whose coils spread and bunch with the true extension, a polished
//  block riding a rail, force/velocity/acceleration arrows, energy
//  bars, ghost turning-points while held, and a floating scrolling
//  graph of the motion the user can walk around.
//
//  The helix is one TubeMesh built once and scaled along its axis —
//  exactly how a real spring's coils redistribute, at zero per-frame
//  mesh cost. Ticked per frame from SceneEvents.Update.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class SpringsRenderer {
    let root = Entity()
    /// Freeze sculpts: paused blocks grow velocity and spring-force
    /// arrows — at the turning points the velocity arrow vanishes and
    /// the force arrow peaks, which IS simple harmonic motion.
    private let frozenVectors = FrozenVectors(budget: 8)
    var subscriptions: [EventSubscription] = []

    /// Block index a hand is holding (system-dragged entity).
    var grabbedBlock: Int?

    let infoAnchor = Entity()

    private let steelMaterial = SimpleMaterial(
        color: UIColor(white: 0.85, alpha: 1), roughness: 0.15, isMetallic: true)
    private let aluminumMaterial = Materials.energized(
        UIColor(white: 0.7, alpha: 1), roughness: 0.3, metallic: 1.0, glow: 0.0)
    private let springMaterial = Materials.energized(
        UIColor(red: 0.75, green: 0.76, blue: 0.8, alpha: 1),
        roughness: 0.22, metallic: 1.0, glow: 0.0)
    /// The block: polished machined metal — clear-coat gloss over metal,
    /// no glow (a mass, not a source).
    private static let blockMaterial = Materials.energized(
        UIColor(white: 0.82, alpha: 1), roughness: 0.12, metallic: 1.0, glow: 0.0)

    private var blocks: [ModelEntity] = []
    private var springs: [ModelEntity] = []
    private var supports: [ModelEntity] = []
    private let rail: ModelEntity

    // The period tag at the spring's anchor — T = 2π√(m/k), the number
    // the stiffness and mass sliders are actually steering. Hidden in
    // coupled mode (two normal modes; one T would mislead).
    private let periodHolder = Entity()
    private var periodText: ModelEntity!
    private var periodKey = ""
    private var periodMeshCache: [String: MeshResource] = [:]
    private let periodMaterial = UnlitMaterial(color: UIColor(
        red: 0.0, green: 0.55, blue: 0.52, alpha: 1))
    private let velocityArrow = PendulumsRenderer.Arrow(
        color: UIColor(red: 0.25, green: 0.55, blue: 1, alpha: 1))
    private let accelerationArrow = PendulumsRenderer.Arrow(
        color: UIColor(red: 1, green: 0.55, blue: 0.1, alpha: 1))
    private let forceArrow = PendulumsRenderer.Arrow(
        color: UIColor(red: 0.2, green: 0.8, blue: 0.35, alpha: 1))

    // Energy bars: KE blue, PE green, total white.
    private let kineticBar: ModelEntity
    private let potentialBar: ModelEntity
    private let totalBar: ModelEntity
    private let energyRoot = Entity()
    private static let barFullHeight: Float = 0.4

    // Ghost turning points while held.
    private let ghostA: ModelEntity
    private let ghostB: ModelEntity

    // Scrolling graph: pooled dots + glowing marker.
    private let graphRoot = Entity()
    private let graphPool: EntityPool<Void>
    private let graphMarker: ModelEntity
    private static let graphWidth: Float = 0.7
    private static let graphHeight: Float = 0.34
    /// How far the time axis runs into the room.
    private static let graphDepth: Float = 0.85

    private static func helixMesh() -> MeshResource? {
        // 9 coils, unit length along Y.
        let coils = 9.0
        let radius: Float = 0.032
        let points = (0...260).map { step -> SIMD3<Float> in
            let t = Float(step) / 260
            let phi = Float(2 * .pi * coils) * t
            return SIMD3(radius * cos(phi), t, radius * sin(phi))
        }
        return TubeMesh.tube(lines: [points], radius: 0.0045, sides: 6)
    }

    init() {
        root.addChild(Lighting.keyLight())
        // Supports and rail.
        let supportMesh = MeshResource.generateBox(
            size: [0.05, 0.34, 0.1], cornerRadius: 0.01)
        for side: Double in [-1, 1] {
            let support = ModelEntity(mesh: supportMesh, materials: [aluminumMaterial])
            support.position = SIMD3<Float>(
                SpringsModel.center + SIMD3(side * SpringsModel.railHalfLength, 0, 0))
            supports.append(support)
            root.addChild(support)
        }
        rail = ModelEntity(
            mesh: .generateCylinder(height: Float(2 * SpringsModel.railHalfLength), radius: 0.005),
            materials: [aluminumMaterial])
        rail.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        rail.position = SIMD3<Float>(SpringsModel.center)
        root.addChild(rail)

        let periodPivot = Entity()
        periodPivot.components.set(BillboardComponent())
        periodText = ModelEntity()
        periodPivot.addChild(periodText)
        periodHolder.addChild(periodPivot)
        root.addChild(periodHolder)

        // Blocks (up to 2) and springs (up to 3), enabled per mode.
        let blockMesh = MeshResource.generateBox(size: [0.09, 0.08, 0.08], cornerRadius: 0.012)
        for index in 0..<2 {
            let block = ModelEntity(mesh: blockMesh, materials: [Self.blockMaterial])
            block.name = "s-block-\(index)"
            Grabbable.configureTouchTarget(block, collisionRadius: 0.1)
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = "Spring block. Pull it along the rail and let go."
            block.components.set(accessibility)
            blocks.append(block)
            root.addChild(block)
        }
        let helix = Self.helixMesh()
        for _ in 0..<3 {
            let spring = ModelEntity()
            if let helix {
                spring.model = ModelComponent(mesh: helix, materials: [springMaterial])
            }
            springs.append(spring)
            root.addChild(spring)
        }

        root.addChild(velocityArrow.holder)
        root.addChild(accelerationArrow.holder)
        root.addChild(forceArrow.holder)

        // Glowing glossy columns — they read as energy, not plastic bars.
        let kineticMaterial = Materials.energized(
            UIColor(red: 0.25, green: 0.5, blue: 1, alpha: 1), roughness: 0.25, glow: 0.4)
        let potentialMaterial = Materials.energized(
            UIColor(red: 0.2, green: 0.8, blue: 0.35, alpha: 1), roughness: 0.25, glow: 0.4)
        var totalMaterial = UnlitMaterial(color: UIColor(white: 0.9, alpha: 1))
        totalMaterial.blending = .transparent(opacity: 0.4)
        let barMesh = MeshResource.generateBox(size: [0.045, 1, 0.045], cornerRadius: 0.008)
        kineticBar = ModelEntity(mesh: barMesh, materials: [kineticMaterial])
        potentialBar = ModelEntity(mesh: barMesh, materials: [potentialMaterial])
        totalBar = ModelEntity(mesh: barMesh, materials: [totalMaterial])
        energyRoot.position = SIMD3<Float>(SpringsModel.center) + SIMD3(-1.0, 0.05, 0)
        kineticBar.position = [0, 0, 0]
        potentialBar.position = [0.08, 0, 0]
        totalBar.position = [0.16, 0, 0]
        energyRoot.addChild(kineticBar)
        energyRoot.addChild(potentialBar)
        energyRoot.addChild(totalBar)
        root.addChild(energyRoot)

        var ghostMaterial = SimpleMaterial(
            color: UIColor(white: 0.9, alpha: 0.25), roughness: 0.3, isMetallic: false)
        ghostMaterial.triangleFillMode = .fill
        ghostA = ModelEntity(mesh: blockMesh, materials: [ghostMaterial])
        ghostB = ModelEntity(mesh: blockMesh, materials: [ghostMaterial])
        ghostA.isEnabled = false
        ghostB.isEnabled = false
        root.addChild(ghostA)
        root.addChild(ghostB)

        // Graph frame and dots.
        graphRoot.position = SIMD3<Float>(SpringsModel.center) + SIMD3(1.05, 0.35, 0)
        var axisMaterial = UnlitMaterial(color: UIColor(white: 0.8, alpha: 1))
        axisMaterial.blending = .transparent(opacity: 0.5)
        let axis = ModelEntity(
            mesh: .generateBox(size: [Self.graphWidth + 0.04, 0.003, 0.003]),
            materials: [axisMaterial])
        graphRoot.addChild(axis)
        let dotMesh = MeshResource.generateSphere(radius: 0.0035)
        var dotMaterial = UnlitMaterial(color: UIColor(red: 0.4, green: 0.85, blue: 1, alpha: 1))
        dotMaterial.blending = .transparent(opacity: 0.9)
        graphPool = EntityPool(budget: SpringsModel.historyCapacity) { container in
            container.addChild(ModelEntity(mesh: dotMesh, materials: [dotMaterial]))
        }
        graphRoot.addChild(graphPool.root)
        graphMarker = ModelEntity(
            mesh: .generateSphere(radius: 0.009),
            materials: [UnlitMaterial(color: UIColor(red: 0.7, green: 0.95, blue: 1, alpha: 1))])
        graphRoot.addChild(graphMarker)
        root.addChild(graphRoot)

        infoAnchor.components.set(BillboardComponent())
        root.addChild(infoAnchor)

        audioEmitter.components.set(SpatialAudioComponent())
        root.addChild(audioEmitter)
    }

    private let audioEmitter = Entity()

    /// A soft whoosh on release, louder for faster pulls.
    func playRelease(speed: Double, at position: SIMD3<Double>) {
        audioEmitter.position = SIMD3<Float>(position)
        SoundPalette.play(.whoosh, on: audioEmitter,
                          volume: min(0.25 + speed * 0.25, 0.85))
    }

    // MARK: Per-frame tick

    func tick(dt: Double, model: SpringsModel) {
        if frozenVectors.root.parent == nil { root.addChild(frozenVectors.root) }
        frozenVectors.update(frozen: model.isPaused, dt: dt) {
            var samples: [FrozenVectors.Sample] = []
            let axis = model.axisDirection
            // Acceleration when a spring is at full stretch — the
            // honest ceiling for the force arrows.
            let aScale = max(model.stiffness * model.maxExtension / model.mass, 1e-6)
            let vScale = max(model.maxExtension
                             * (model.stiffness / model.mass).squareRoot(), 1e-6)

            // Lifted a hand above the rail: the motion is along the
            // rail, so arrows drawn AT the blocks lie exactly along the
            // springs and thread through the coils — only their heads
            // peeked out of the loop gaps. Riding above, they read like
            // annotations over the apparatus.
            let lift = SIMD3<Float>(0, 0.09, 0)
            func add(position: SIMD3<Float>, velocity: Double, accel: Double) {
                let position = position + lift
                if abs(velocity) > 0.005 {
                    samples.append(.init(
                        position: position,
                        direction: SIMD3<Float>(axis * (velocity < 0 ? -1 : 1)),
                        magnitude01: Float(min(abs(velocity) / vScale, 1)),
                        kind: .velocity))
                }
                if abs(accel) > 0.01 {
                    samples.append(.init(
                        position: position,
                        direction: SIMD3<Float>(axis * (accel < 0 ? -1 : 1)),
                        magnitude01: Float(min(abs(accel) / aScale, 1)),
                        kind: .force))
                }
            }

            switch model.mode {
            case .single:
                add(position: self.blocks[0].position,
                    velocity: model.state.velocity,
                    accel: model.acceleration)
            case .coupled:
                // F₁ = −kx₁ + k_c(x₂−x₁), and its mirror — the coupling
                // term is what carries the energy across.
                let x = model.coupled.displacements
                let v = model.coupled.velocities
                let forces = SIMD2(
                    -model.stiffness * x.x + model.coupling * (x.y - x.x),
                    -model.stiffness * x.y + model.coupling * (x.x - x.y))
                for index in 0..<2 {
                    add(position: self.blocks[index].position,
                        velocity: v[index],
                        accel: forces[index] / model.mass)
                }
            }
            return samples
        }
        model.step(dt: dt)
        syncApparatus(model)
        syncPeriodLabel(model)
        syncArrowsAndEnergy(model)
        syncGhost(model)
        syncGraph(model)

        let blockWorld = model.mode == .single
            ? model.blockWorld : model.coupledBlockWorld(0)
        let cardOffset: SIMD3<Float> = model.orientation == .vertical
            ? [0.2, 0, 0] : [0, 0.14, 0]
        infoAnchor.position = SIMD3<Float>(blockWorld) + cardOffset
    }

    /// Aim a helix spring between two world points.
    private func layoutSpring(_ spring: ModelEntity, from a: SIMD3<Double>, to b: SIMD3<Double>) {
        let span = SIMD3<Float>(b - a)
        let length = simd_length(span)
        guard length > 1e-4 else {
            spring.isEnabled = false
            return
        }
        spring.isEnabled = true
        spring.position = SIMD3<Float>(a)
        spring.orientation = VectorFieldArrows.rotationFromYAxis(to: span / length)
        spring.scale = SIMD3(1, length, 1)
    }

    private func syncPeriodLabel(_ model: SpringsModel) {
        guard model.mode == .single else {
            periodHolder.isEnabled = false
            return
        }
        periodHolder.isEnabled = true
        periodHolder.position = SIMD3<Float>(model.anchorWorld) + SIMD3(0, 0.17, 0)

        let string = String(format: "T = %.2f s", model.period)
        guard periodKey != string else { return }
        periodKey = string
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
        periodText.model = ModelComponent(mesh: mesh, materials: [periodMaterial])
        let bounds = mesh.bounds
        periodText.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
    }

    private func syncApparatus(_ model: SpringsModel) {
        let leftAnchor = SpringsModel.center + SIMD3(-SpringsModel.railHalfLength, 0, 0)
        let rightAnchor = SpringsModel.center + SIMD3(SpringsModel.railHalfLength, 0, 0)

        // Rig the supports and rail for the current orientation.
        let vertical = model.orientation == .vertical
        if vertical {
            supports[0].position = SIMD3<Float>(model.anchorWorld + SIMD3(0, 0.02, 0))
            supports[0].orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            supports[1].isEnabled = false
            rail.orientation = .init(angle: 0, axis: [0, 1, 0])
            rail.position = SIMD3<Float>(model.anchorWorld + SIMD3(0, -0.55, 0))
        } else {
            supports[0].position = SIMD3<Float>(
                SpringsModel.center + SIMD3(-SpringsModel.railHalfLength, 0, 0))
            supports[0].orientation = .init(angle: 0, axis: [0, 1, 0])
            supports[1].isEnabled = true
            rail.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            rail.position = SIMD3<Float>(SpringsModel.center)
        }

        switch model.mode {
        case .single:
            blocks[1].isEnabled = false
            springs[1].isEnabled = false
            springs[2].isEnabled = false
            blocks[0].isEnabled = true
            // The block never leaves its rail: even while grabbed, the
            // visual rides the axis-projected model position (the hand
            // only supplies the displacement through the router).
            let blockWorld = model.blockWorld
            blocks[0].position = SIMD3<Float>(blockWorld)
            // The block slides; it never spins. Lock the twist a hand
            // gives it back to the rail's frame, every frame.
            blocks[0].orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            layoutSpring(springs[0], from: model.anchorWorld,
                         to: blockWorld - model.axisDirection * 0.045)
        case .coupled:
            for index in 0..<2 {
                blocks[index].isEnabled = true
                blocks[index].position = SIMD3<Float>(model.coupledBlockWorld(index))
                blocks[index].orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            }
            let b0 = model.coupledBlockWorld(0)
            let b1 = model.coupledBlockWorld(1)
            layoutSpring(springs[0], from: leftAnchor, to: b0 - SIMD3(0.045, 0, 0))
            layoutSpring(springs[1], from: b0 + SIMD3(0.045, 0, 0), to: b1 - SIMD3(0.045, 0, 0))
            layoutSpring(springs[2], from: b1 + SIMD3(0.045, 0, 0), to: rightAnchor)
        }
    }

    private func syncArrowsAndEnergy(_ model: SpringsModel) {
        let vertical = model.orientation == .vertical
        let perpendicular: SIMD3<Float> = vertical ? [0.09, 0, 0] : [0, 0.07, 0]
        let origin = SIMD3<Float>(model.mode == .single
                                  ? model.blockWorld : model.coupledBlockWorld(0))
            + perpendicular
        let axis = model.axisDirection

        let velocity = model.mode == .single
            ? model.state.velocity : model.coupled.velocities.x
        velocityArrow.holder.isEnabled = model.showVelocity
        if model.showVelocity {
            velocityArrow.update(origin: origin,
                                 vector: axis * velocity, reference: 0.4)
        }
        accelerationArrow.holder.isEnabled = model.showAcceleration
        if model.showAcceleration {
            accelerationArrow.update(origin: origin + perpendicular * 0.7,
                                     vector: axis * model.acceleration, reference: 3)
        }
        forceArrow.holder.isEnabled = model.showForce
        if model.showForce {
            forceArrow.update(origin: origin + perpendicular * 1.4,
                              vector: axis * model.springForce, reference: 4)
        }

        guard model.showEnergyBars else {
            energyRoot.isEnabled = false
            return
        }
        energyRoot.isEnabled = true
        let energies = model.mode == .single
            ? model.energies()
            : {
                let pair = model.coupled.massEnergies(
                    stiffness: model.stiffness, coupling: model.coupling,
                    masses: SIMD2(model.mass, model.mass))
                return (kinetic: pair.x, potential: pair.y)
            }()
        let total = max(energies.kinetic + energies.potential, 1e-6)
        let reference = max(total, 0.05)
        func size(_ bar: ModelEntity, _ energy: Double, offset: Float) {
            let height = max(Float(energy / reference) * Self.barFullHeight, 0.004)
            bar.scale = [1, height, 1]
            bar.position = [offset, height / 2, 0]
        }
        size(kineticBar, energies.kinetic, offset: 0)
        size(potentialBar, energies.potential, offset: 0.08)
        size(totalBar, total, offset: 0.16)
    }

    private func syncGhost(_ model: SpringsModel) {
        guard model.showGhost, model.grabbedBlock == 0, model.mode == .single else {
            ghostA.isEnabled = false
            ghostB.isEnabled = false
            return
        }
        // Turning points a release right now would reach.
        let amplitude = model.predictedAmplitude()
        let anchor = model.anchorWorld + model.axisDirection * model.restLength
        ghostA.isEnabled = true
        ghostB.isEnabled = true
        ghostA.position = SIMD3<Float>(anchor + model.axisDirection * amplitude)
        ghostB.position = SIMD3<Float>(anchor - model.axisDirection * amplitude)
    }

    private func syncGraph(_ model: SpringsModel) {
        let history = model.history
        let count = history.count
        // Fixed, readable scales per mode.
        let scale: Double
        switch model.graphMode {
        case .position: scale = 0.36
        case .velocity: scale = 1.6
        case .acceleration: scale = 16
        case .energy: scale = max(history.max() ?? 1, 0.01) * 1.2
        }
        // The trace RECEDES: time runs away from the viewer in depth.
        //
        // A position-versus-time plot painted on a vertical plane is a
        // wall chart, and a wall chart is not worth wearing a headset
        // for. Extruding the time axis into the room turns it into a
        // ribbon you can lean around: the block's motion is happening
        // at the near end, and its whole history trails off behind, so
        // "the past" is somewhere you can physically look. The values
        // are identical — only the axis moved out of the plane.
        for (index, slot) in graphPool.slots.enumerated() {
            guard index < count else {
                slot.entity.isEnabled = false
                continue
            }
            slot.entity.isEnabled = true
            let fraction = Float(index) / Float(SpringsModel.historyCapacity - 1)
            let value = history[index]
            let y = Float(min(max(value / scale, -1), 1)) * Self.graphHeight / 2
            slot.entity.position = Self.graphPoint(fraction: fraction, y: y)
            // Older samples sit further away and shrink with distance,
            // so the ribbon reads as depth rather than as a scatter.
            slot.entity.scale = SIMD3(repeating: 0.45 + 0.55 * fraction)
        }
        if count > 0 {
            graphMarker.isEnabled = true
            let fraction = Float(count - 1) / Float(SpringsModel.historyCapacity - 1)
            let y = Float(min(max(history[count - 1] / scale, -1), 1)) * Self.graphHeight / 2
            graphMarker.position = Self.graphPoint(fraction: fraction, y: y)
        } else {
            graphMarker.isEnabled = false
        }
    }

    /// Where a sample sits on the receding time ribbon. `fraction` 0 is
    /// the oldest sample (furthest away), 1 the newest (nearest).
    private static func graphPoint(fraction: Float, y: Float) -> SIMD3<Float> {
        SIMD3(-graphWidth / 2 + fraction * graphWidth * 0.35,
              y,
              -graphDepth * (1 - fraction))
    }
}
