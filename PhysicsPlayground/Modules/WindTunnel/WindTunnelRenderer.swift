//
//  WindTunnelRenderer.swift
//  Physics Playground — Wind Tunnel module
//
//  Renders the test section: a grabbable cylinder that visibly spins at
//  its true rate (ω = Γ/2πa²), streamlines traced through the exact
//  field with RenderKit's StreamlineTracer, a sheet of air particles
//  advected at true speed, red stagnation dots, the Kutta–Joukowski
//  lift arrow, and the pressure probe.
//
//  Frame-rate contract: particles are pool + transform writes; the
//  streamline tube rebuilds only when a flow input changes, at most
//  every 3rd render.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class WindTunnelRenderer {
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    static let cylinderName = "cylinder"
    static let probeName = "probe"
    static let sectionCenter = SIMD3<Float>(0, 0.92, -1.1)
    /// Height of the flow sheet above the section floor.
    static let flowHeight: Float = 0.055

    var isManipulatingCylinder = false
    var isManipulatingProbe = false

    /// Parent for the probe's floating readout attachment.
    let probeAnchor = Entity()

    private static let particleBudget = 350
    private static let particleLife = 12.0
    private static let baseCylinderRadius: Float = 0.05

    private let sectionRoot = Entity()
    private let cylinder: ModelEntity
    private let spinMarker: ModelEntity
    private let streamlineEntity = ModelEntity()
    private let streamlineMaterial: UnlitMaterial
    private var stagnationMarkers: [ModelEntity] = []
    private let liftArrowShaft: ModelEntity
    private let liftArrowHead: ModelEntity
    private let liftArrow = Entity()
    private let probe: ModelEntity

    private let particlePool: EntityPool<Void>
    private var particlePositions: [SIMD2<Double>] = []
    private var particleAges: [Double] = []
    private var particlesVisible = false

    private let renderLoop = RenderLoop()
    private var model: WindTunnelModel?
    private var frameCounter = 0

    private struct FlowInputs: Equatable {
        var speed: Double
        var center: SIMD2<Double>
        var radius: Double
        var circulation: Double
        var show: Bool
    }
    private var lastFlowInputs: FlowInputs?
    private var streamlinesDirty = true

    init() {
        sectionRoot.position = Self.sectionCenter
        root.addChild(sectionRoot)

        // Section floor and the two side rails (ends stay open — the
        // flow enters on the left and leaves on the right).
        let floor = ModelEntity(
            mesh: .generateBox(size: [1.28, 0.012, 0.86], cornerRadius: 0.005),
            materials: [SimpleMaterial(color: UIColor(white: 0.15, alpha: 1),
                                       roughness: 0.85, isMetallic: false)]
        )
        floor.position = [0, -0.006, 0]
        sectionRoot.addChild(floor)

        let railMesh = MeshResource.generateBox(size: [1.28, 0.05, 0.025])
        let railMaterial = SimpleMaterial(
            color: UIColor(white: 0.24, alpha: 1), roughness: 0.7, isMetallic: false)
        for sign: Float in [1, -1] {
            let rail = ModelEntity(mesh: railMesh, materials: [railMaterial])
            rail.position = [0, 0.025, sign * (Float(WindTunnelModel.halfWidth) + 0.0325)]
            sectionRoot.addChild(rail)
        }

        // The cylinder — grabbable, and it visibly spins at its true rate.
        cylinder = ModelEntity(
            mesh: .generateCylinder(height: 0.14, radius: Self.baseCylinderRadius),
            materials: [SimpleMaterial(color: DesignTokens.Palette.launcherUI,
                                       roughness: 0.35, isMetallic: true)]
        )
        cylinder.name = Self.cylinderName
        Grabbable.configure(cylinder, collisionRadius: 0.11)
        var cylinderAccessibility = AccessibilityComponent()
        cylinderAccessibility.isAccessibilityElement = true
        cylinderAccessibility.label = "Cylinder. Drag it through the flow; the streamlines re-form instantly."
        cylinder.components.set(cylinderAccessibility)
        spinMarker = ModelEntity(
            mesh: .generateBox(size: [0.012, 0.13, 0.006]),
            materials: [UnlitMaterial(color: UIColor(white: 0.05, alpha: 1))]
        )
        spinMarker.position = [Self.baseCylinderRadius - 0.004, 0, 0]
        cylinder.addChild(spinMarker)
        sectionRoot.addChild(cylinder)

        // Streamlines.
        var streamMaterial = UnlitMaterial(color: DesignTokens.Palette.streamlineUI)
        streamMaterial.blending = .transparent(opacity: 0.6)
        streamlineMaterial = streamMaterial
        sectionRoot.addChild(streamlineEntity)

        // Stagnation points: where the air comes to rest on the surface.
        let stagnationMesh = MeshResource.generateSphere(radius: 0.007)
        let stagnationMaterial = UnlitMaterial(color: DesignTokens.Palette.forceVectorUI)
        for _ in 0..<2 {
            let marker = ModelEntity(mesh: stagnationMesh, materials: [stagnationMaterial])
            marker.isEnabled = false
            stagnationMarkers.append(marker)
            sectionRoot.addChild(marker)
        }

        // Lift arrow (Kutta–Joukowski), floating above the cylinder.
        let liftMaterial = UnlitMaterial(color: DesignTokens.Palette.forceVectorUI)
        liftArrowShaft = ModelEntity(
            mesh: .generateCylinder(height: 0.1, radius: 0.004), materials: [liftMaterial])
        liftArrowHead = ModelEntity(
            mesh: .generateCone(height: 0.03, radius: 0.011), materials: [liftMaterial])
        liftArrow.addChild(liftArrowShaft)
        liftArrow.addChild(liftArrowHead)
        liftArrow.isEnabled = false
        sectionRoot.addChild(liftArrow)

        // Probe.
        probe = ModelEntity(
            mesh: .generateSphere(radius: 0.014),
            materials: [UnlitMaterial(color: .white)]
        )
        probe.name = Self.probeName
        Grabbable.configure(probe, collisionRadius: 0.045)
        var probeAccessibility = AccessibilityComponent()
        probeAccessibility.isAccessibilityElement = true
        probeAccessibility.label = "Pressure probe. Park it anywhere to read the local air speed and pressure."
        probe.components.set(probeAccessibility)
        sectionRoot.addChild(probe)

        probeAnchor.components.set(BillboardComponent())
        sectionRoot.addChild(probeAnchor)

        // Air particles: one sheet at cylinder mid-height.
        var particleMaterial = UnlitMaterial(color: .white)
        particleMaterial.blending = .transparent(opacity: 0.4)
        let particleMesh = MeshResource.generateSphere(radius: 0.0026)
        particlePool = EntityPool(budget: Self.particleBudget) { container in
            container.addChild(ModelEntity(mesh: particleMesh, materials: [particleMaterial]))
        }
        particlePositions = (0..<Self.particleBudget).map { _ in Self.randomEntryPoint(anywhere: true) }
        particleAges = (0..<Self.particleBudget).map { _ in Double.random(in: 0..<Self.particleLife) }
        sectionRoot.addChild(particlePool.root)
    }

    // MARK: Per-frame tick (particles + true-rate spin animation)

    func tick(dt: Double, model: WindTunnelModel) {
        guard !model.isPaused else { return }
        let scaledDt = dt * model.timeScale

        // The cylinder turns at the spin rate its circulation implies.
        let omega = model.circulation
            / (2 * .pi * model.cylinderRadius * model.cylinderRadius)
        if abs(omega) > 1e-6 {
            cylinder.orientation = simd_quatf(angle: Float(omega * scaledDt), axis: [0, 1, 0])
                * cylinder.orientation
        }

        guard model.showParticles else {
            if particlesVisible {
                particlePool.hideAll()
                particlesVisible = false
            }
            return
        }
        particlesVisible = true

        let flow = model.flow
        for index in 0..<Self.particleBudget {
            var position = particlePositions[index]
            particleAges[index] += dt
            let velocity = flow.velocity(at: position)
            position += velocity * scaledDt

            let insideCylinder = simd_distance(position, flow.center) < flow.radius * 1.02
            if position.x > WindTunnelModel.halfLength
                || abs(position.y) > WindTunnelModel.halfWidth
                || insideCylinder
                || particleAges[index] > Self.particleLife {
                position = Self.randomEntryPoint(anywhere: false)
                particleAges[index] = 0
            }
            particlePositions[index] = position

            let slot = particlePool.slots[index]
            slot.entity.isEnabled = true
            slot.entity.position = SIMD3(
                Float(position.x), Self.flowHeight, Float(position.y))
        }
    }

    private static func randomEntryPoint(anywhere: Bool) -> SIMD2<Double> {
        SIMD2(
            anywhere ? .random(in: -WindTunnelModel.halfLength...WindTunnelModel.halfLength)
                     : -WindTunnelModel.halfLength,
            .random(in: -WindTunnelModel.halfWidth...WindTunnelModel.halfWidth)
        )
    }

    // MARK: Render loop

    func startObserving(_ model: WindTunnelModel) {
        self.model = model
        renderLoop.start { [weak self, weak model] in
            guard let self, let model else { return }
            self.render(model)
        }
    }

    /// World point → plane coordinates (meters from the section center).
    func planePoint(fromWorld world: SIMD3<Float>) -> SIMD2<Double> {
        let local = world - Self.sectionCenter
        return SIMD2(Double(local.x), Double(local.z))
    }

    private func render(_ model: WindTunnelModel) {
        frameCounter &+= 1

        if !isManipulatingCylinder {
            cylinder.position = SIMD3(
                Float(model.cylinderCenter.x), 0.07, Float(model.cylinderCenter.y))
        }
        let radiusScale = Float(model.cylinderRadius) / Self.baseCylinderRadius
        cylinder.scale = SIMD3(radiusScale, 1, radiusScale)

        if !isManipulatingProbe {
            probe.position = SIMD3(
                Float(model.probePosition.x), Self.flowHeight + 0.02, Float(model.probePosition.y))
        }
        probeAnchor.position = SIMD3(
            Float(model.probePosition.x), 0.22, Float(model.probePosition.y))

        syncStagnationAndLift(model)
        syncStreamlines(model)
    }

    private func syncStagnationAndLift(_ model: WindTunnelModel) {
        let points = model.stagnationPoints
        for (index, marker) in stagnationMarkers.enumerated() {
            guard index < points.count else {
                marker.isEnabled = false
                continue
            }
            marker.isEnabled = true
            marker.position = SIMD3(Float(points[index].x), 0.07, Float(points[index].y))
        }

        let lift = model.liftPerSpan
        guard abs(lift) > 0.02 else {
            liftArrow.isEnabled = false
            return
        }
        liftArrow.isEnabled = true
        liftArrow.position = SIMD3(
            Float(model.cylinderCenter.x), 0.19, Float(model.cylinderCenter.y))
        // Lift acts along ±y in plane coordinates = ±z in the room.
        let direction = SIMD3<Float>(0, 0, lift > 0 ? 1 : -1)
        let length = Float(min(0.05 + 0.09 * log10(1 + abs(lift) / 0.1), 0.24))
        liftArrow.orientation = VectorFieldArrows.rotationFromYAxis(to: direction)
        liftArrowShaft.scale = [1, length / 0.1, 1]
        liftArrowShaft.position = [0, length / 2, 0]
        liftArrowHead.position = [0, length + 0.015, 0]
    }

    private func syncStreamlines(_ model: WindTunnelModel) {
        let inputs = FlowInputs(
            speed: model.windSpeed, center: model.cylinderCenter,
            radius: model.cylinderRadius, circulation: model.circulation,
            show: model.showStreamlines
        )
        if inputs != lastFlowInputs {
            lastFlowInputs = inputs
            streamlinesDirty = true
        }
        guard streamlinesDirty, frameCounter % 3 == 0 else { return }
        streamlinesDirty = false

        guard model.showStreamlines else {
            streamlineEntity.model = nil
            return
        }

        let flow = model.flow
        var config = StreamlineTracer.Config()
        config.stepSize = 0.01
        config.maxSteps = 220
        config.boundsCenter = .zero
        config.boundsRadius = 0.85
        config.stopCenters = [SIMD3(flow.center.x, 0, flow.center.y)]
        config.stopRadius = flow.radius * 1.01

        var lines: [[SIMD3<Float>]] = []
        let seedCount = 13
        for index in 0..<seedCount {
            let fraction = Double(index) / Double(seedCount - 1)
            let y = -WindTunnelModel.halfWidth + 0.04
                + fraction * 2 * (WindTunnelModel.halfWidth - 0.04)
            let seed = SIMD3(-WindTunnelModel.halfLength + 0.02, 0, y)
            let line = StreamlineTracer.streamline(
                from: seed, sign: 1,
                field: { point in
                    let v = flow.velocity(at: SIMD2(point.x, point.z))
                    return SIMD3(v.x, 0, v.y)
                },
                config: config
            )
            if line.count > 1 {
                lines.append(line.map {
                    SIMD3(Float($0.x), Self.flowHeight, Float($0.z))
                })
            }
        }

        if let mesh = TubeMesh.tube(lines: lines, radius: 0.0013, sides: 3) {
            streamlineEntity.model = ModelComponent(mesh: mesh, materials: [streamlineMaterial])
        } else {
            streamlineEntity.model = nil
        }
    }
}
