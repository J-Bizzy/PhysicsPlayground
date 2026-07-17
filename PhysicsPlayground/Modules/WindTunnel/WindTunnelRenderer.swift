//
//  WindTunnelRenderer.swift
//  Physics Playground — Wind Tunnel module
//
//  Renders the test section as a fully volumetric block of moving air
//  floating in the room — no table, no furniture. A tall grabbable
//  cylinder visibly spins at its true rate (ω = Γ/2πa²); streamline
//  sheets at three heights bend around it (the extruded-cylinder field
//  is exact at every height); a 3D cloud of air particles rides the
//  flow at true speed; red vertical STAGNATION LINES (that's what they
//  are on a cylinder) slide with spin; the Kutta–Joukowski lift arrow
//  floats above; the pressure probe roams freely in 3D.
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
    static let sectionCenter = SIMD3<Float>(0, 1.3, -1.2)
    /// Half-height of the airflow volume (cylinder spans it fully).
    static let halfHeight: Float = 0.45

    var isManipulatingCylinder = false
    var isManipulatingProbe = false
    /// The probe floats freely; its height is visual (the extruded field
    /// is identical at every height — that's the point).
    var probeHeight: Float = 0.1

    /// Parent for the probe's floating readout attachment.
    let probeAnchor = Entity()

    private static let particleBudget = 440
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
    private var particleHeights: [Float] = []
    private var particleAges: [Double] = []
    private var particlesVisible = false

    /// Holder for the non-cylinder drag bodies; the current USDZ clone
    /// is its only child.
    private let dragBodyHolder = Entity()
    private var shownDragBody: DragBody?
    private static var dragBodyPrototypes: [DragBody: Entity] = [:]
    private static let dragBodyAssets: [DragBody: String] = [
        .sphere: "DragSphere", .teardrop: "DragTeardrop", .cube: "DragCube",
        .flatDisc: "DragDisc", .cone: "DragCone",
    ]
    /// The frontal radius the USDZ bodies were authored at.
    private static let authoredBodyRadius = 0.06

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

        // The cylinder — a tall column spanning the airflow volume,
        // grabbable, visibly spinning at its true rate.
        cylinder = ModelEntity(
            mesh: .generateCylinder(height: 2 * Self.halfHeight, radius: Self.baseCylinderRadius),
            materials: [SimpleMaterial(color: DesignTokens.Palette.launcherUI,
                                       roughness: 0.35, isMetallic: true)]
        )
        cylinder.name = Self.cylinderName
        Grabbable.configure(cylinder, collisionRadius: 0.16)
        var cylinderAccessibility = AccessibilityComponent()
        cylinderAccessibility.isAccessibilityElement = true
        cylinderAccessibility.label = "Cylinder. Drag it through the flow; the streamlines re-form instantly."
        cylinder.components.set(cylinderAccessibility)
        spinMarker = ModelEntity(
            mesh: .generateBox(size: [0.012, 2 * Self.halfHeight - 0.02, 0.006]),
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

        // Stagnation LINES: on a cylinder the air comes to rest along a
        // whole vertical line, not a point — drawn as thin red columns.
        let stagnationMesh = MeshResource.generateBox(
            size: [0.006, 2 * Self.halfHeight, 0.006], cornerRadius: 0.003)
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

        // The interchangeable drag bodies (Blender-authored USDZ, frontal
        // radius 0.06 as authored) share the cylinder's name so the same
        // grab gesture carries whichever body is in the section.
        dragBodyHolder.name = Self.cylinderName
        Grabbable.configure(dragBodyHolder, collisionRadius: 0.16)
        var dragAccessibility = AccessibilityComponent()
        dragAccessibility.isAccessibilityElement = true
        dragAccessibility.label = "Drag test body. Carry it through the flow."
        dragBodyHolder.components.set(dragAccessibility)
        dragBodyHolder.isEnabled = false
        sectionRoot.addChild(dragBodyHolder)

        // Air particles: a full 3D cloud (the extruded field is exact at
        // every height, so every layer of air moves identically).
        var particleMaterial = UnlitMaterial(color: .white)
        particleMaterial.blending = .transparent(opacity: 0.4)
        let particleMesh = MeshResource.generateSphere(radius: 0.0026)
        particlePool = EntityPool(budget: Self.particleBudget) { container in
            container.addChild(ModelEntity(mesh: particleMesh, materials: [particleMaterial]))
        }
        particlePositions = (0..<Self.particleBudget).map { _ in Self.randomEntryPoint(anywhere: true) }
        particleHeights = (0..<Self.particleBudget).map { _ in
            Float.random(in: -Self.halfHeight...Self.halfHeight)
        }
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
        let obstacles = model.obstacles
        let sectionCenter = SIMD3<Double>(Self.sectionCenter)
        for index in 0..<Self.particleBudget {
            var position = particlePositions[index]
            var height = Double(particleHeights[index])
            particleAges[index] += dt

            // The plane field (exact for the cylinder; the same ideal
            // deflection visualizes the other bodies), then any real-room
            // obstacles bend the full 3D velocity in world space.
            let planar = flow.velocity(at: position)
            var velocity3 = SIMD3(planar.x, 0, planar.y)
            if !obstacles.spheres.isEmpty {
                let world = sectionCenter + SIMD3(position.x, height, position.y)
                velocity3 = obstacles.deflected(velocity3, at: world)
            }
            position += SIMD2(velocity3.x, velocity3.z) * scaledDt
            height = min(max(height + velocity3.y * scaledDt,
                             -Double(Self.halfHeight)), Double(Self.halfHeight))

            let insideCylinder = simd_distance(position, flow.center) < flow.radius * 1.02
            if position.x > WindTunnelModel.halfLength
                || abs(position.y) > WindTunnelModel.halfWidth
                || insideCylinder
                || particleAges[index] > Self.particleLife {
                position = Self.randomEntryPoint(anywhere: false)
                height = Double(Float.random(in: -Self.halfHeight...Self.halfHeight))
                particleAges[index] = 0
            }
            particlePositions[index] = position
            particleHeights[index] = Float(height)

            let slot = particlePool.slots[index]
            slot.entity.isEnabled = true
            slot.entity.position = SIMD3(
                Float(position.x), particleHeights[index], Float(position.y))
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

        syncTestBody(model)

        let bodyEntity = model.testBody == .cylinder ? cylinder : dragBodyHolder
        if !isManipulatingCylinder {
            bodyEntity.position = SIMD3(
                Float(model.cylinderCenter.x), 0, Float(model.cylinderCenter.y))
        }
        if model.testBody == .cylinder {
            let radiusScale = Float(model.cylinderRadius) / Self.baseCylinderRadius
            cylinder.scale = SIMD3(radiusScale, 1, radiusScale)
        } else {
            let scale = Float(model.cylinderRadius / Self.authoredBodyRadius)
            dragBodyHolder.scale = SIMD3(repeating: scale)
        }

        // The probe reads the cylinder's exact field — for the empirical
        // drag bodies it would be fiction, so it rests.
        probe.isEnabled = model.testBody == .cylinder
        probeAnchor.isEnabled = model.testBody == .cylinder
        if !isManipulatingProbe {
            probe.position = SIMD3(
                Float(model.probePosition.x), probeHeight, Float(model.probePosition.y))
        }
        probeAnchor.position = SIMD3(
            Float(model.probePosition.x), probeHeight + 0.09, Float(model.probePosition.y))

        syncStagnationAndLift(model)
        syncStreamlines(model)
    }

    /// Shows the selected test body: the spinning cylinder, or a clone
    /// of the matching Blender-authored USDZ.
    private func syncTestBody(_ model: WindTunnelModel) {
        cylinder.isEnabled = model.testBody == .cylinder
        dragBodyHolder.isEnabled = model.testBody != .cylinder
        guard model.testBody != .cylinder, shownDragBody != model.testBody else { return }
        shownDragBody = model.testBody

        for child in Array(dragBodyHolder.children) {
            child.removeFromParent()
        }
        guard let asset = Self.dragBodyAssets[model.testBody] else { return }
        if Self.dragBodyPrototypes[model.testBody] == nil,
           let loaded = try? Entity.load(named: asset) {
            Self.dragBodyPrototypes[model.testBody] = loaded
        }
        if let prototype = Self.dragBodyPrototypes[model.testBody] {
            dragBodyHolder.addChild(prototype.clone(recursive: true))
        } else {
            // Fallback: a simple sphere so the section is never empty.
            dragBodyHolder.addChild(ModelEntity(
                mesh: .generateSphere(radius: Float(Self.authoredBodyRadius)),
                materials: [SimpleMaterial(color: DesignTokens.Palette.launcherUI,
                                           roughness: 0.4, isMetallic: true)]))
        }
    }

    private func syncStagnationAndLift(_ model: WindTunnelModel) {
        // Stagnation lines belong to the cylinder's exact solution.
        let points = model.testBody == .cylinder ? model.stagnationPoints : []
        for (index, marker) in stagnationMarkers.enumerated() {
            guard index < points.count else {
                marker.isEnabled = false
                continue
            }
            marker.isEnabled = true
            marker.position = SIMD3(Float(points[index].x), 0, Float(points[index].y))
        }

        // Cylinder mode: the KJ lift arrow (across the flow). Drag-lab
        // mode: the same arrow becomes the DRAG arrow, pointing
        // downstream with F = ½ρv²CdA setting its length.
        let isCylinder = model.testBody == .cylinder
        let magnitude = isCylinder ? abs(model.liftPerSpan) : model.dragForce
        let threshold = isCylinder ? 0.02 : 0.001
        guard magnitude > threshold else {
            liftArrow.isEnabled = false
            return
        }
        liftArrow.isEnabled = true
        liftArrow.position = SIMD3(
            Float(model.cylinderCenter.x), Self.halfHeight + 0.06, Float(model.cylinderCenter.y))
        let direction: SIMD3<Float> = isCylinder
            ? SIMD3(0, 0, model.liftPerSpan > 0 ? 1 : -1)   // across the flow
            : SIMD3(1, 0, 0)                                 // downstream
        let reference = isCylinder ? 0.1 : 0.02
        let length = Float(min(0.05 + 0.09 * log10(1 + magnitude / reference), 0.24))
        liftArrow.orientation = VectorFieldArrows.rotationFromYAxis(to: direction)
        liftArrowShaft.scale = [1, length / 0.1, 1]
        liftArrowShaft.position = [0, length / 2, 0]
        liftArrowHead.position = [0, length + 0.015, 0]
    }

    private func syncStreamlines(_ model: WindTunnelModel) {
        let inputs = FlowInputs(
            speed: model.windSpeed, center: model.cylinderCenter,
            radius: model.cylinderRadius, circulation: model.circulation,
            show: model.showStreamlines && model.testBody == .cylinder
        )
        if inputs != lastFlowInputs {
            lastFlowInputs = inputs
            streamlinesDirty = true
        }
        guard streamlinesDirty, frameCounter % 3 == 0 else { return }
        streamlinesDirty = false

        guard model.showStreamlines, model.testBody == .cylinder else {
            streamlineEntity.model = nil
            return
        }

        let flow = model.flow
        var config = StreamlineTracer.Config()
        config.stepSize = 0.01
        config.maxSteps = 300
        config.boundsCenter = .zero
        config.boundsRadius = 1.5
        config.stopCenters = [SIMD3(flow.center.x, 0, flow.center.y)]
        config.stopRadius = flow.radius * 1.01

        // Three sheets of streamlines: the extruded field is exact at
        // every height, and the stack makes the flow read as a volume.
        var lines: [[SIMD3<Float>]] = []
        let seedCount = 9
        for sheetHeight: Float in [-0.32, 0, 0.32] {
            for index in 0..<seedCount {
                let fraction = Double(index) / Double(seedCount - 1)
                let y = -WindTunnelModel.halfWidth + 0.05
                    + fraction * 2 * (WindTunnelModel.halfWidth - 0.05)
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
                        SIMD3(Float($0.x), sheetHeight, Float($0.z))
                    })
                }
            }
        }

        if let mesh = TubeMesh.tube(lines: lines, radius: 0.0013, sides: 3) {
            streamlineEntity.model = ModelComponent(mesh: mesh, materials: [streamlineMaterial])
        } else {
            streamlineEntity.model = nil
        }
    }
}
