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
//  writes. Trail tubes rebuild staggered (each body at most every 8th
//  render); the prediction tube rebuilds at most every 4th render while
//  a body is held.
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

    /// Set by the space view's router while the hand owns a body.
    var manipulatingBodyID: UUID?

    /// Where the system center sits in the room.
    static let systemPosition = SIMD3<Float>(0, 1.25, -1.2)

    /// Parent for the selected body's floating data panel (the space view
    /// attaches the SwiftUI attachment here; we move it each render).
    let selectedAnchor = Entity()

    private let systemRoot = Entity()
    private let scale = Float(GravityLabModel.simToDisplay)

    private let bodyPool: EntityPool<ModelEntity>
    private var bodyMaterialKeys: [String]
    private var bodyNames: [String]
    private static let baseBodyRadius: Float = 0.05

    private let trailPool: EntityPool<Void>
    private var trailEntities: [ModelEntity] = []
    private var trailBuiltCounts: [Int]
    private var trailMaterialKeys: [String]

    private let sunLight = Entity()
    private let predictionEntity = ModelEntity()
    private let predictionMaterial: UnlitMaterial
    private let flashEntity: ModelEntity

    private struct Arrow {
        let container: Entity
        let shaft: ModelEntity
        let head: ModelEntity
    }
    private var velocityArrow: Arrow!
    private var accelerationArrow: Arrow!
    private var forceArrow: Arrow!

    private let renderLoop = RenderLoop()
    private var model: GravityLabModel?
    private var frameCounter = 0
    private var lastMergeNonce = 0

    init() {
        systemRoot.position = Self.systemPosition
        root.addChild(systemRoot)

        // The floating platform under the system — a quiet glass disc.
        var platformMaterial = UnlitMaterial(color: .black)
        platformMaterial.blending = .transparent(opacity: 0.35)
        let platform = ModelEntity(
            mesh: .generateCylinder(height: 0.006, radius: 0.55),
            materials: [platformMaterial]
        )
        platform.position = [0, -0.42, 0]
        systemRoot.addChild(platform)

        // Bodies.
        let bodyMesh = MeshResource.generateSphere(radius: Self.baseBodyRadius)
        bodyPool = EntityPool(budget: GravityLabModel.bodyBudget) { container in
            let sphere = ModelEntity(
                mesh: bodyMesh,
                materials: [SimpleMaterial(color: .white, roughness: 0.6, isMetallic: false)]
            )
            Grabbable.configure(sphere, collisionRadius: Self.baseBodyRadius * 1.5)
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

        // The Sun's light: warm, following the heaviest body.
        sunLight.components.set(PointLightComponent(
            color: UIColor(red: 1.0, green: 0.9, blue: 0.75, alpha: 1),
            intensity: 12_000,
            attenuationRadius: 5
        ))
        systemRoot.addChild(sunLight)

        // Trails: one tube entity per body slot.
        trailPool = EntityPool(budget: GravityLabModel.bodyBudget) { _ in }
        for slot in trailPool.slots {
            let tube = ModelEntity()
            slot.entity.addChild(tube)
            slot.entity.isEnabled = true
            trailEntities.append(tube)
        }
        trailBuiltCounts = Array(repeating: -1, count: trailPool.budget)
        trailMaterialKeys = Array(repeating: "", count: trailPool.budget)
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
    }

    private static func makeArrow(color: UIColor) -> Arrow {
        let material = UnlitMaterial(color: color)
        let shaft = ModelEntity(
            mesh: .generateCylinder(height: 0.1, radius: 0.0035), materials: [material])
        let head = ModelEntity(
            mesh: .generateCone(height: 0.028, radius: 0.010), materials: [material])
        let container = Entity()
        container.addChild(shaft)
        container.addChild(head)
        container.isEnabled = false
        return Arrow(container: container, shaft: shaft, head: head)
    }

    // MARK: Render loop

    func startObserving(_ model: GravityLabModel) {
        self.model = model
        renderLoop.start { [weak self, weak model] in
            guard let self, let model else { return }
            self.render(model)
        }
    }

    /// Room coordinates → display coordinates relative to the system center.
    func displayPoint(fromWorld world: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3<Double>(world - Self.systemPosition)
    }

    private func render(_ model: GravityLabModel) {
        frameCounter &+= 1
        syncBodies(model)
        syncTrails(model)
        syncPrediction(model)
        syncVectors(model)
        syncMergeFlash(model)
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
            if bodyMaterialKeys[index] != orbiting.body.name {
                bodyMaterialKeys[index] = orbiting.body.name
                slot.payload.model?.materials = [Self.material(for: orbiting.body.name)]
            }
            slot.entity.scale = SIMD3<Float>(
                repeating: Float(orbiting.displayRadius) / Self.baseBodyRadius)

            if orbiting.id == manipulatingBodyID {
                // Hand owns the sphere: leave transforms alone.
            } else {
                slot.entity.position = SIMD3<Float>(orbiting.body.position) * scale
                slot.payload.position = .zero
            }
        }
        for index in model.bodies.count..<bodyPool.budget {
            bodyPool.slots[index].entity.isEnabled = false
        }

        if let primary = model.primaryBody {
            sunLight.position = SIMD3<Float>(primary.body.position) * scale
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

    private static func material(for name: String) -> RealityKit.Material {
        if name == "Sun" {
            // Unlit = self-luminous against the room.
            return UnlitMaterial(color: DesignTokens.Palette.celestialUI(name))
        }
        return SimpleMaterial(
            color: DesignTokens.Palette.celestialUI(name), roughness: 0.55, isMetallic: false)
    }

    // MARK: Trails

    private func syncTrails(_ model: GravityLabModel) {
        for index in 0..<trailPool.budget {
            guard index < model.bodies.count else {
                trailEntities[index].model = nil
                trailBuiltCounts[index] = -1
                continue
            }
            let orbiting = model.bodies[index]
            // Staggered rebuilds: each body's tube refreshes at most every
            // 8th render, and only when its trail actually grew.
            guard (frameCounter + index) % 8 == 0,
                  orbiting.trail.count != trailBuiltCounts[index] else { continue }
            trailBuiltCounts[index] = orbiting.trail.count

            let points = orbiting.trail.map { SIMD3<Float>($0) * scale }
            if points.count >= 2, let mesh = TubeMesh.tube(lines: [points], radius: 0.0012) {
                if trailMaterialKeys[index] != orbiting.body.name {
                    trailMaterialKeys[index] = orbiting.body.name
                }
                var material = UnlitMaterial(color: DesignTokens.Palette.celestialUI(orbiting.body.name))
                material.blending = .transparent(opacity: 0.5)
                trailEntities[index].model = ModelComponent(mesh: mesh, materials: [material])
            } else {
                trailEntities[index].model = nil
            }
        }
    }

    // MARK: Held-body prediction

    private func syncPrediction(_ model: GravityLabModel) {
        guard model.heldBodyID != nil else {
            predictionEntity.model = nil
            return
        }
        guard frameCounter % 4 == 0 else { return }
        let points = model.heldPrediction().map { SIMD3<Float>($0) * scale }
        if points.count >= 2, let mesh = TubeMesh.tube(lines: [points], radius: 0.002) {
            predictionEntity.model = ModelComponent(mesh: mesh, materials: [predictionMaterial])
        } else {
            predictionEntity.model = nil
        }
    }

    // MARK: Vectors (lengths are log-scaled; the legend says so)

    private func syncVectors(_ model: GravityLabModel) {
        guard let selected = model.selectedBody,
              let readout = model.readout(for: selected),
              selected.id != manipulatingBodyID else {
            velocityArrow.container.isEnabled = false
            accelerationArrow.container.isEnabled = false
            forceArrow.container.isEnabled = false
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
            arrow.container.isEnabled = false
            return
        }
        let l = Float(min(max(length, 0.02), 0.3))
        arrow.container.isEnabled = true
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
