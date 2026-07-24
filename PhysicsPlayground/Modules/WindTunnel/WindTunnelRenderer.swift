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

    private static let baseCylinderRadius: Float = 0.05

    private let sectionRoot = Entity()
    private let cylinder: ModelEntity
    private let spinMarker: ModelEntity
    /// One tube entity per speed color — CFD-plot style: red where the
    /// air stagnates against the body, cyan where it whips around it.
    private var streamlineBuckets: [ModelEntity] = []
    /// A smoke palette: the filaments read as lit vapour first and a CFD
    /// plot second. Speed still colours them — air piled up against the
    /// nose warms toward amber, air whipping around the shoulders cools
    /// toward blue — but everything sits close to white, so the tunnel
    /// looks like a tunnel instead of a rainbow.
    private static let streamlineColors: [UIColor] = [
        UIColor(red: 1.00, green: 0.72, blue: 0.45, alpha: 1),  // stagnant
        UIColor(red: 1.00, green: 0.88, blue: 0.74, alpha: 1),
        UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1),
        UIColor(red: 0.96, green: 0.98, blue: 1.00, alpha: 1),  // free stream
        UIColor(red: 0.72, green: 0.88, blue: 1.00, alpha: 1),  // accelerated
    ]
    /// The industrial fan the wind pours out of — free-floating, its
    /// blades spun by the wind slider.
    private var fanEntity: Entity?
    private var fanBlades: Entity?
    private var fanHum: AudioPlaybackController?
    private var fanHumGain = -100.0
    private var stagnationMarkers: [ModelEntity] = []
    private let liftArrowShaft: ModelEntity
    private let liftArrowHead: ModelEntity
    private let liftArrow = Entity()
    private let probe: ModelEntity

    /// The live incompressible flow solve (its own actor, off-main).
    private let solver = WindFlowSolver()
    private var solveInFlight = false
    private var flowAccumulator = 0.0

    /// The whole smoke cloud: one entity, one mesh of soft puff sprites.
    private let smokeEntity = ModelEntity()
    private lazy var smokeMaterial: UnlitMaterial = Self.makeSmokeMaterial()

    /// A soft radial puff: opaque-ish in the middle, feathering to
    /// nothing at the rim. Overlapping these is what makes the wake read
    /// as volume instead of as a swarm of dots.
    private static func makeSmokeMaterial() -> UnlitMaterial {
        var material = UnlitMaterial(color: .white)
        // The falloff has to drive OPACITY. A base-colour texture's alpha
        // is not used for transparency here — supplying it that way gave
        // dark, hard-edged squares instead of soft puffs.
        guard let texture = puffTexture() else {
            material.blending = .transparent(opacity: 0.35)
            return material
        }
        material.color = .init(tint: .white)
        // Each puff is faint on its own; density comes from many of them
        // overlapping. Individually-opaque sprites read as a pile of
        // coins, not as smoke. This sits high enough that white vapour
        // still reads against a brightly-lit passthrough wall, which is
        // the hard case — over a dark surface it is comfortably visible.
        material.blending = .transparent(
            opacity: .init(scale: 0.40, texture: .init(texture)))
        return material
    }

    /// A greyscale radial falloff, written into every channel so it reads
    /// correctly whichever one the opacity map samples: bright at the
    /// centre, zero at the rim, so overlapping puffs blend into haze with
    /// no sprite edge anywhere.
    private static func puffTexture() -> TextureResource? {
        let side = 64
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let centre = Float(side - 1) / 2
        for y in 0..<side {
            for x in 0..<side {
                let dx = (Float(x) - centre) / centre
                let dy = (Float(y) - centre) / centre
                let r = min(sqrt(dx * dx + dy * dy), 1)
                let falloff = powf(1 - r, 2.0)
                let value = UInt8(max(0, min(255, falloff * 255)))
                let index = (y * side + x) * 4
                bytes[index] = value; bytes[index + 1] = value
                bytes[index + 2] = value; bytes[index + 3] = value
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent) else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .raw))
    }

    /// Holder for the non-cylinder drag bodies; the current USDZ clone
    /// is its only child.
    private let dragBodyHolder = Entity()
    private var shownDragBody: DragBody?
    private static var dragBodyPrototypes: [DragBody: Entity] = [:]
    private static let dragBodyAssets: [DragBody: String] = [
        .sphere: "DragSphere", .teardrop: "DragTeardrop", .cube: "DragCube",
        .flatDisc: "DragDisc", .cone: "DragCone",
        .car: "DragCar", .truck: "DragTruck", .plane: "DragPlane",
    ]
    /// The frontal radius the USDZ bodies were authored at.
    private static let authoredBodyRadius = 0.06

    private let beamRoot = Entity()
    /// Where the beam pours from: the fan's face, in section coords —
    /// carried with the fan wherever it's parked.
    private var fanMouth = SIMD3<Double>(-WindTunnelModel.halfLength - 0.10, 0, 0)

    init() {
        root.addChild(Lighting.keyLight())
        sectionRoot.position = Self.sectionCenter
        root.addChild(sectionRoot)

        // The cylinder — a tall column spanning the airflow volume,
        // grabbable, visibly spinning at its true rate.
        cylinder = ModelEntity(
            mesh: .generateCylinder(height: 2 * Self.halfHeight, radius: Self.baseCylinderRadius),
            materials: [Materials.energized(DesignTokens.Palette.launcherUI,
                                            roughness: 0.3, metallic: 1.0, glow: 0.0)]
        )
        cylinder.name = Self.cylinderName
        Grabbable.configureTouchTarget(cylinder, collisionRadius: 0.16)
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

        // Streamlines: five color buckets, slow→red through fast→cyan.
        // They hang under beamRoot, which translates rigidly with the
        // carried fan so the beam sticks to the duct while the
        // background re-trace catches up (the EM warp pattern).
        sectionRoot.addChild(beamRoot)
        for color in Self.streamlineColors {
            let entity = ModelEntity()
            streamlineBuckets.append(entity)
            beamRoot.addChild(entity)
            _ = color  // materials applied at mesh build
        }

        // The fan at the tunnel mouth: grab it and park it anywhere;
        // its blades spin with the wind.
        if let fan = try? Entity.load(named: "TunnelFan") {
            fan.name = "fan"
            fan.position = SIMD3(-Float(WindTunnelModel.halfLength) - 0.24, 0, 0)
            Grabbable.configureTouchTarget(fan, collisionRadius: 0.48)
            var fanAccessibility = AccessibilityComponent()
            fanAccessibility.isAccessibilityElement = true
            fanAccessibility.label = "Wind fan. Its blades spin with the wind speed; carry it anywhere."
            fan.components.set(fanAccessibility)
            sectionRoot.addChild(fan)
            fanEntity = fan
            fanBlades = fan.findEntity(named: "FanBlades")
        }

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
            materials: [Materials.energized(.white, roughness: 0.25, glow: 0.18)]
        )
        probe.name = Self.probeName
        Grabbable.configureTouchTarget(probe, collisionRadius: 0.045)
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
        Grabbable.configureTouchTarget(dragBodyHolder, collisionRadius: 0.16)
        var dragAccessibility = AccessibilityComponent()
        dragAccessibility.isAccessibilityElement = true
        dragAccessibility.label = "Drag test body. Carry it through the flow."
        dragBodyHolder.components.set(dragAccessibility)
        dragBodyHolder.isEnabled = false
        sectionRoot.addChild(dragBodyHolder)

        // The smoke cloud: a single entity whose mesh the solver rebuilds.
        sectionRoot.addChild(smokeEntity)
    }

    // MARK: Per-frame tick (particles + true-rate spin animation)

    func tick(dt: Double, model: WindTunnelModel) {
        // Rendered here every frame (the observation loop can starve on
        // an idle scene — the circuits lesson) so streamline rebuilds
        // and slider edits always land.
        render(model)

        guard !model.isPaused else { return }
        let scaledDt = dt * model.timeScale

        // The fan spins with the wind it's making — and sounds like it:
        // the hum's gain rides the wind slider, silent while paused.
        if let fanBlades {
            fanBlades.orientation = simd_quatf(
                angle: Float(model.windSpeed * 7 * scaledDt), axis: [1, 0, 0])
                * fanBlades.orientation
        }
        if let fanEntity {
            if fanHum == nil {
                fanHum = SoundPalette.startFanHum(on: fanEntity)
            }
            let target = model.isPaused ? -100.0 : (-40.0 + 13.0 * model.windSpeed)
            if abs(target - fanHumGain) > 0.5 {
                fanHumGain = target
                fanEntity.components.set(SpatialAudioComponent(gain: Audio.Decibel(target)))
            }
        }

        // The cylinder turns at the spin rate its circulation implies.
        let omega = model.circulation
            / (2 * .pi * model.cylinderRadius * model.cylinderRadius)
        if abs(omega) > 1e-6 {
            cylinder.orientation = simd_quatf(angle: Float(omega * scaledDt), axis: [0, 1, 0])
                * cylinder.orientation
        }

        driveSolver(dt: scaledDt, model: model)
    }

    // MARK: The live CFD flow
    //
    // Every frame the solver actor is handed whatever is currently in the
    // stream — the test body, plus the user's tracked hands and any
    // reconstructed room surfaces — advances the incompressible solve one
    // step off the main thread, and hands back finished tube geometry and
    // smoke positions. Requests never queue: while one is in flight the
    // elapsed time simply accumulates, so a slow solve costs frame rate
    // in the flow's smoothness, never in the app's responsiveness.

    private func driveSolver(dt: Double, model: WindTunnelModel) {
        flowAccumulator += dt
        guard !solveInFlight, flowAccumulator > 1.0 / 60.0 else { return }
        let step = min(flowAccumulator, 1.0 / 20.0)
        flowAccumulator = 0
        solveInFlight = true

        let obstacles = solidObstacles(for: model)
        let inflow = model.windSpeed
        let wantRibbons = model.showStreamlines
        let wantSmoke = model.showParticles

        Task { [weak self] in
            guard let self else { return }
            await solver.setInflow(inflow)
            await solver.setObstacles(obstacles)
            await solver.primeIfNeeded()
            let snapshot = await solver.advance(
                dt: step, traceRibbons: wantRibbons, smokeVisible: wantSmoke)
            self.applyFlow(snapshot, model: model)
            self.solveInFlight = false
        }
    }

    /// Everything the air has to get around, in section-local coordinates:
    /// the test body's silhouette, and — on device — the ARKit hands and
    /// room mesh that make the wind react to the real world.
    private func solidObstacles(for model: WindTunnelModel) -> [WindFlowSolver.Obstacle] {
        var obstacles: [WindFlowSolver.Obstacle] = []
        if model.testBody == .cylinder {
            // The cylinder is a column: a stack of balls up its span.
            let radius = model.cylinderRadius
            let halfSpan = min(Double(Self.halfHeight), WindTunnelModel.cylinderSpan / 2)
            var y = -halfSpan
            while y <= halfSpan {
                obstacles.append(.init(
                    center: SIMD3(model.cylinderCenter.x, y, model.cylinderCenter.y),
                    radius: radius))
                y += radius * 0.9
            }
        } else {
            obstacles = model.bodyObstacles.spheres.map {
                .init(center: $0.center, radius: $0.radius)
            }
        }
        // Real-room obstacles arrive in world space.
        let sectionCenter = SIMD3<Double>(Self.sectionCenter)
        obstacles += model.obstacles.spheres.map {
            .init(center: $0.center - sectionCenter, radius: $0.radius)
        }
        return obstacles
    }

    private func applyFlow(_ snapshot: WindFlowSolver.Snapshot, model: WindTunnelModel) {
        // Streamline ribbons — one mesh per speed-colour bucket.
        if model.showStreamlines, !snapshot.ribbonBuffers.isEmpty {
            for (index, entity) in streamlineBuckets.enumerated() {
                guard index < snapshot.ribbonBuffers.count,
                      let mesh = TubeMesh.mesh(from: snapshot.ribbonBuffers[index]) else {
                    entity.model = nil
                    continue
                }
                var material = UnlitMaterial(color: Self.streamlineColors[index])
                material.blending = .transparent(opacity: 0.75)
                entity.model = ModelComponent(mesh: mesh, materials: [material])
            }
        } else if !model.showStreamlines {
            for bucket in streamlineBuckets { bucket.model = nil }
        }

        // Smoke: ONE sprite mesh, uploaded whole. Hundreds of separate
        // entities meant hundreds of transform writes and draw calls a
        // frame; this is a single upload and a single draw.
        guard model.showParticles, !snapshot.smoke.isEmpty else {
            smokeEntity.model = nil
            return
        }
        var descriptor = MeshDescriptor(name: "smoke")
        descriptor.positions = MeshBuffer(snapshot.smoke.positions)
        descriptor.normals = MeshBuffer(snapshot.smoke.normals)
        descriptor.textureCoordinates = MeshBuffer(snapshot.smoke.uvs)
        descriptor.primitives = .triangles(snapshot.smoke.indices)
        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            smokeEntity.model = ModelComponent(mesh: mesh, materials: [smokeMaterial])
        }
    }

    /// The fan's world position, for the relative-drag session.
    func fanWorldPosition() -> SIMD3<Double>? {
        fanEntity.map { SIMD3<Double>($0.position(relativeTo: nil)) }
    }

    /// Moves the fan (world coords) — called by the drag, so the fan
    /// only ever moves by the hand's displacement.
    func moveFan(toWorld position: SIMD3<Double>) {
        fanEntity?.setPosition(SIMD3<Float>(position), relativeTo: nil)
    }

    /// World point → plane coordinates (meters from the section center).
    func planePoint(fromWorld world: SIMD3<Float>) -> SIMD2<Double> {
        let local = world - Self.sectionCenter
        return SIMD2(Double(local.x), Double(local.z))
    }

    private func render(_ model: WindTunnelModel) {
        if let fanEntity {
            let p = fanEntity.position
            fanMouth = SIMD3(Double(p.x) + 0.14, Double(p.y), Double(p.z))
        }
        // The solved flow lives in the section's own frame — the working
        // section is fixed in the room, so the ribbons need no warping.
        beamRoot.position = .zero

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
        // Streamlines are no longer traced here: they come from the live
        // solve, arriving with the smoke in applyFlow.
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

    /// Local speed ratio → color bucket: red at stagnation, green in the
    /// free stream, cyan where the body squeezes the air faster.
    private nonisolated static func speedBucket(_ ratio: Double) -> Int {
        switch ratio {
        case ..<0.40: 0
        case ..<0.72: 1
        case ..<0.95: 2
        case ..<1.08: 3
        default: 4
        }
    }

}
