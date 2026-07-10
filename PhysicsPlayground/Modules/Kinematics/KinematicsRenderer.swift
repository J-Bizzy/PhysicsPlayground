//
//  KinematicsRenderer.swift
//  Physics Playground — Kinematics module
//
//  Renders the 1:10 tabletop diorama: a plate with real-meter tick lines,
//  the launcher (barrel + grabbable aim bead), the live predicted arc,
//  and pooled projectiles with strobe-dot trails.
//
//  Frame-rate contract: pools are built once (EntityPool); per-frame work
//  is transform writes only. The predicted-arc tube mesh rebuilds only
//  when an aim input actually changes.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class KinematicsRenderer {
    /// Root of everything we render, added to RealityView content at identity.
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    /// While the user is dragging the aim bead, the manipulation system
    /// owns its position — the render loop must not fight it.
    var isManipulatingBead = false

    static let aimBeadName = "aimBead"

    /// Where the diorama sits in the room (launch point = this position).
    static let dioramaPosition = SIMD3<Float>(-0.55, 0.95, -1.05)

    private static let barrelLength: Float = 0.07
    private static let beadDistance: Float = 0.10
    private static let baseProjectileRadius: Float = 0.01
    /// Small balls are enlarged to stay visible (legend says so).
    private static let minimumDisplayRadius: Float = 0.005

    private let scale = Float(KinematicsModel.displayScale)
    private let dioramaRoot = Entity()
    private let barrel: ModelEntity
    private let bead: ModelEntity
    private let arcEntity = ModelEntity()
    private let arcMaterial: UnlitMaterial
    private let projectilePool: EntityPool<ModelEntity>
    private let dotPool: EntityPool<Void>
    private let renderLoop = RenderLoop()
    private var model: KinematicsModel?

    // Change detection: the arc tube only rebuilds when these differ.
    private var lastAim: SIMD3<Double>?
    private var lastSpeed: Double?
    private var lastGravity: Double?
    private var lastAir: Bool?
    private var lastKind: KinematicsModel.ProjectileKind?

    init() {
        dioramaRoot.position = Self.dioramaPosition
        root.addChild(dioramaRoot)

        // Plate: top surface exactly at physics ground level (y = 0).
        let plateLength = Float(KinematicsModel.tableMaxX - KinematicsModel.tableMinX) * scale
        let plateDepth = Float(2 * KinematicsModel.tableHalfDepth) * scale
        let plate = ModelEntity(
            mesh: .generateBox(size: [plateLength, 0.03, plateDepth], cornerRadius: 0.008),
            materials: [SimpleMaterial(color: UIColor(white: 0.22, alpha: 1), roughness: 0.9, isMetallic: false)]
        )
        plate.position = [Float(KinematicsModel.tableMinX + KinematicsModel.tableMaxX) / 2 * scale, -0.015, 0]
        dioramaRoot.addChild(plate)

        // Tick lines across the plate every real meter downrange.
        var tickMaterial = UnlitMaterial(color: .white)
        tickMaterial.blending = .transparent(opacity: 0.28)
        let tickMesh = MeshResource.generateBox(size: [0.0015, 0.0008, plateDepth])
        for meter in 0...Int(KinematicsModel.tableMaxX) {
            let tick = ModelEntity(mesh: tickMesh, materials: [tickMaterial])
            tick.position = [Float(meter) * scale, 0.0005, 0]
            dioramaRoot.addChild(tick)
        }

        // Launcher: a small base disc, a barrel from the muzzle along the
        // aim direction (projectiles emerge from its tip), and the aim bead.
        let launcherMaterial = SimpleMaterial(
            color: DesignTokens.Palette.launcherUI, roughness: 0.4, isMetallic: true)
        let base = ModelEntity(
            mesh: .generateCylinder(height: 0.006, radius: 0.024),
            materials: [launcherMaterial]
        )
        base.position = [0, 0.003, 0]
        dioramaRoot.addChild(base)

        barrel = ModelEntity(
            mesh: .generateCylinder(height: Self.barrelLength, radius: 0.008),
            materials: [launcherMaterial]
        )
        dioramaRoot.addChild(barrel)

        bead = ModelEntity(
            mesh: .generateSphere(radius: 0.011),
            materials: [UnlitMaterial(color: DesignTokens.Palette.projectileUI)]
        )
        bead.name = Self.aimBeadName
        Grabbable.configure(bead, collisionRadius: 0.035)
        var beadAccessibility = AccessibilityComponent()
        beadAccessibility.isAccessibilityElement = true
        beadAccessibility.label = "Aim bead. Drag to point the launcher."
        bead.components.set(beadAccessibility)
        dioramaRoot.addChild(bead)

        // Predicted arc.
        var arcMaterial = UnlitMaterial(color: DesignTokens.Palette.predictedArcUI)
        arcMaterial.blending = .transparent(opacity: 0.5)
        self.arcMaterial = arcMaterial
        dioramaRoot.addChild(arcEntity)

        // Pools: identical meshes shared across slots, sized per flight by
        // scaling the container.
        let projectileMesh = MeshResource.generateSphere(radius: Self.baseProjectileRadius)
        let projectileMaterial = SimpleMaterial(
            color: DesignTokens.Palette.projectileUI, roughness: 0.4, isMetallic: false)
        projectilePool = EntityPool(budget: KinematicsModel.flightBudget) { container in
            let sphere = ModelEntity(mesh: projectileMesh, materials: [projectileMaterial])
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = "Projectile"
            sphere.components.set(accessibility)
            container.addChild(sphere)
            return sphere
        }
        dioramaRoot.addChild(projectilePool.root)

        var dotMaterial = UnlitMaterial(color: DesignTokens.Palette.projectileUI)
        dotMaterial.blending = .transparent(opacity: 0.7)
        let dotMesh = MeshResource.generateSphere(radius: 0.0035)
        dotPool = EntityPool(
            budget: KinematicsModel.flightBudget * KinematicsModel.dotsPerFlight
        ) { container in
            container.addChild(ModelEntity(mesh: dotMesh, materials: [dotMaterial]))
        }
        dioramaRoot.addChild(dotPool.root)
    }

    // MARK: Render loop

    func startObserving(_ model: KinematicsModel) {
        self.model = model
        renderLoop.start { [weak self, weak model] in
            guard let self, let model else { return }
            self.render(model)
        }
    }

    /// Converts a scene-space point (e.g. from a manipulation event) into
    /// physics space, in real meters relative to the muzzle.
    func physicsPoint(fromWorld world: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3<Double>(world - Self.dioramaPosition) / KinematicsModel.displayScale
    }

    private func render(_ model: KinematicsModel) {
        let aim = model.aimDirection
        let aimDisplay = SIMD3<Float>(aim)

        // Launcher follows the aim; the bead too, unless the hand owns it.
        barrel.orientation = VectorFieldArrows.rotationFromYAxis(to: aimDisplay)
        barrel.position = (Self.barrelLength / 2) * aimDisplay
        if !isManipulatingBead {
            bead.position = Self.beadDistance * aimDisplay
        }

        // Predicted arc — rebuild only when an input actually changed.
        if aim != lastAim || model.launchSpeed != lastSpeed || model.gravity != lastGravity
            || model.airResistance != lastAir || model.kind != lastKind {
            let points = model.prediction.points.map { SIMD3<Float>($0) * scale }
            if let mesh = TubeMesh.tube(lines: [points], radius: 0.0018) {
                arcEntity.model = ModelComponent(mesh: mesh, materials: [arcMaterial])
            } else {
                arcEntity.model = nil
            }
            lastAim = aim
            lastSpeed = model.launchSpeed
            lastGravity = model.gravity
            lastAir = model.airResistance
            lastKind = model.kind
        }

        syncFlights(model.flights)
    }

    private func syncFlights(_ flights: [KinematicsModel.Flight]) {
        for (index, slot) in projectilePool.slots.enumerated() {
            guard index < flights.count else {
                slot.entity.isEnabled = false
                continue
            }
            let flight = flights[index]
            slot.entity.isEnabled = flight.status != .offTable
            slot.entity.position = SIMD3<Float>(flight.state.position) * scale
            slot.entity.scale = SIMD3<Float>(
                repeating: displayRadius(for: flight.kind) / Self.baseProjectileRadius)
        }

        // Strobe dots, flattened across flights in order.
        var dotIndex = 0
        for flight in flights {
            for dot in flight.dots where dotIndex < dotPool.budget {
                let slot = dotPool.slots[dotIndex]
                slot.entity.isEnabled = true
                slot.entity.position = SIMD3<Float>(dot) * scale
                dotIndex += 1
            }
        }
        for index in dotIndex..<dotPool.budget {
            dotPool.slots[index].entity.isEnabled = false
        }
    }

    private func displayRadius(for kind: KinematicsModel.ProjectileKind) -> Float {
        max(Float(kind.projectile.diameter / 2) * scale, Self.minimumDisplayRadius)
    }
}
