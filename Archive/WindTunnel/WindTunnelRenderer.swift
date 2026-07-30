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
import Metal
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
    /// The half-extents of the region worth sampling when the flow is
    /// frozen — the working volume the smoke actually occupies, not the
    /// whole grid, so no arrows are spent on dead corners. The solver's
    /// coordinates ARE these section-local coordinates (the smoke's
    /// inlet points live in this same frame), so a sample needs no
    /// conversion on its way into the field.
    static let sectionHalfExtents = SIMD3<Float>(0.95, 0.34, 0.42)
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

    /// The test-section frame every body position is expressed in;
    /// blooms convert through it.
    let sectionRoot = Entity()
    /// Freeze sculpts: pausing the tunnel stops the smoke and grows
    /// velocity arrows through the whole test section — the flow field
    /// as a lattice you walk into and read, which is the one thing a
    /// wind tunnel behind glass can never let you do.
    /// Short arrows on a coarse lattice: the field should read as a
    /// field you can walk into, not a thicket you cannot see the car
    /// through.
    private let frozenVectors = FrozenVectors(budget: 100,
                                              minLength: 0.03, maxLength: 0.10)
    private let cylinder: ModelEntity
    private let spinMarker: ModelEntity
    /// The speed palette, re-pitched for a BRIGHT room.
    ///
    /// The old ramp sat deliberately close to white so the filaments
    /// read as vapour — and in a cream-walled living room they read as
    /// nothing at all: white smoke on a white ceiling has no luminance
    /// contrast, and the whole flow field disappeared. Realism that is
    /// invisible is not realism.
    ///
    /// This keeps the same physical encoding (warm = piled up and
    /// slowed at the nose, cool = accelerated over the shoulders) but
    /// pushes saturation and drops value, so every filament is DARKER
    /// than the room behind it and the colour is carrying the pressure
    /// story rather than decorating it. Paired with a dark casing on
    /// the ribbons, this is legible against paint, a window, or the
    /// dimming shell alike.
    private static let streamlineColors: [UIColor] = [
        UIColor(red: 0.85, green: 0.24, blue: 0.10, alpha: 1),  // stagnant, high pressure
        UIColor(red: 0.93, green: 0.55, blue: 0.16, alpha: 1),
        UIColor(red: 0.36, green: 0.42, blue: 0.52, alpha: 1),  // free stream
        UIColor(red: 0.16, green: 0.52, blue: 0.82, alpha: 1),
        UIColor(red: 0.11, green: 0.78, blue: 0.92, alpha: 1),  // accelerated, low pressure
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

    // The smoke and streamlines live HERE, not on the solver, and are
    // rebuilt every frame. The solve lands a dozen times a second; the
    // renderer keeps the last TWO fields and blends between them as it
    // samples, so the visuals morph continuously instead of stepping
    // whenever a snapshot arrives.
    private var currentField: FlowField?
    private var previousField: FlowField?
    /// 0→1 progress from previousField toward currentField.
    private var fieldBlend: Float = 1
    private var fieldElapsed = 0.0
    private var fieldInterval = 1.0 / 12.0
    /// The blend, materialised ONCE per frame so every sample afterwards
    /// reads a single field instead of lerping two — half the sampling
    /// cost across smoke and ribbons. Ping-pong buffers so the previous
    /// frame's field (still referenced by an in-flight ribbon job) never
    /// forces a copy-on-write.
    private var blendedField: FlowField?
    private var blendScratchA: [SIMD3<Float>] = []
    private var blendScratchB: [SIMD3<Float>] = []
    private var blendUseA = true
    private var fieldVersion = 0
    private var lastRibbonBlend: Float = -1
    private var lastRibbonVersion = -1

    /// Fixed-capacity GPU meshes, rewritten in place each frame — the
    /// frame loop never calls MeshResource.generate.
    private var smokeMesh: DynamicMesh?
    private var ribbonMesh: DynamicMesh?
    private var smokeScratch: [Float] = []
    private var smokeIndices: [UInt32] = []
    private var ribbonScratch: [Float] = []
    private var ribbonIndexScratch: [UInt32] = []
    private static let ribbonVertexCapacity =
        ribbonHeights.count * ribbonLaterals.count * ribbonSteps * 2
    private static let ribbonIndexCapacity =
        ribbonHeights.count * ribbonLaterals.count * (ribbonSteps - 1) * 6
    /// One entity for ALL streamlines. Local speed rides each vertex's
    /// texture coordinate into a gradient, so the colour varies
    /// continuously along a filament — cheaper than five bucketed tube
    /// meshes, and with no bucket seams to chop them into dashes.
    private let ribbonEntity = ModelEntity()
    private lazy var ribbonMaterial: UnlitMaterial = Self.makeRibbonMaterial()
    // Counts sized for the Vision Pro's fill-rate budget: two eyes at 4K
    // make stacked translucency the scarcest resource in the app, so the
    // rake and the cloud are as small as they can be while still reading
    // as smoke.
    private static let ribbonHeights: [Double] = [-0.12, -0.04, 0.04, 0.14]
    private static let ribbonLaterals: [Double] = [-0.20, -0.12, -0.04, 0.04, 0.12, 0.20]
    private static let ribbonSteps = 96
    private static let ribbonStride = 0.024
    private static let ribbonHalfWidth = 0.005
    private var smoke: [SIMD3<Double>] = []
    private var smokeAge: [Double] = []
    private static let smokeCount = 520
    /// A mote crosses the 2.1 m section in about two seconds at 1 m/s.
    /// Much more life than that and the ones caught in the slow
    /// recirculation behind a body pile into a wall of smoke.
    private static let smokeLife = 4.0
    private static let smokeSizeNear: Float = 0.008
    private static let smokeSizeFar: Float = 0.017

    /// Motes enter in the band the ribbon rake covers, so the smoke is
    /// dense where the body is instead of thinly filling the tunnel.
    private static func randomInletPoint() -> SIMD3<Double> {
        SIMD3(
            Double.random(in: -1.02 ... -0.90),
            Double.random(in: -0.20 ... 0.28),
            Double.random(in: -0.30 ... 0.30)
        )
    }
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
            opacity: .init(scale: 0.30, texture: .init(texture)))
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
        sectionRoot.addChild(frozenVectors.root)

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
        sectionRoot.addChild(pressureSkin)

        // The fan at the tunnel mouth: grab it and park it anywhere;
        // its blades spin with the wind.
        if let fan = try? Entity.load(named: "TunnelFan") {
            fan.name = "fan"
            fan.position = SIMD3(-Float(WindTunnelModel.halfLength) - 0.24, 0, 0)
            // Sized to the fan itself. At 0.48 the collider reached a
            // quarter-metre INTO the working section and stole pinches
            // meant for the test body — the banned bigger-than-the-
            // visual collider, in miniature.
            Grabbable.configureTouchTarget(fan, collisionRadius: 0.24)
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

        // Smoke and streamlines: fixed-capacity GPU meshes created ONCE;
        // every frame just rewrites their vertex bytes in place.
        let sectionBounds = BoundingBox(min: [-1.15, -0.55, -0.75],
                                        max: [1.15, 0.55, 0.75])
        smokeMesh = DynamicMesh(vertexCapacity: Self.smokeCount * 4,
                                indexCapacity: Self.smokeCount * 6,
                                bounds: sectionBounds)
        ribbonMesh = DynamicMesh(vertexCapacity: Self.ribbonVertexCapacity,
                                 indexCapacity: Self.ribbonIndexCapacity,
                                 bounds: sectionBounds)
        if let smokeMesh {
            smokeEntity.model = ModelComponent(mesh: smokeMesh.resource,
                                               materials: [smokeMaterial])
        }
        if let ribbonMesh {
            ribbonEntity.model = ModelComponent(mesh: ribbonMesh.resource,
                                                materials: [ribbonMaterial])
        }
        // The smoke's quad topology never changes — indices written once.
        smokeIndices.reserveCapacity(Self.smokeCount * 6)
        for m in 0..<Self.smokeCount {
            let b = UInt32(m * 4)
            smokeIndices += [b, b + 1, b + 2, b, b + 2, b + 3]
        }
        sectionRoot.addChild(smokeEntity)
        sectionRoot.addChild(ribbonEntity)
        // Two big transparent meshes occupying the SAME volume have no
        // natural draw order — left ambiguous, the puff quads punch
        // square holes through the ribbons behind them. Pin the order:
        // ribbons first, smoke composited over them.
        let flowSortGroup = ModelSortGroup(depthPass: nil)
        ribbonEntity.components.set(ModelSortGroupComponent(group: flowSortGroup, order: 0))
        smokeEntity.components.set(ModelSortGroupComponent(group: flowSortGroup, order: 1))
    }

    // MARK: Per-frame tick (particles + true-rate spin animation)

    func tick(dt: Double, model: WindTunnelModel) {
        // Rendered here every frame (the observation loop can starve on
        // an idle scene — the circuits lesson) so streamline rebuilds
        // and slider edits always land.
        render(model)

        // The frozen lattice: sampled from the SAME blended field the
        // smoke is advected on, so the arrows and the smoke can never
        // disagree. Only built while frozen — the closure is not even
        // called otherwise.
        frozenVectors.update(frozen: model.isPaused, dt: dt) { [weak self] in
            guard let self, let field = self.blendedField else { return [] }
            var samples: [FrozenVectors.Sample] = []
            let span = Self.sectionHalfExtents
            let steps = SIMD3<Int>(5, 4, 5)
            let reference = Float(max(model.windSpeed, 0.1))
            for ix in 0..<steps.x {
                for iy in 0..<steps.y {
                    for iz in 0..<steps.z {
                        // Split out: the one-expression version of this
                        // defeated the type checker.
                        let fx: Float = (Float(ix) + 0.5) / Float(steps.x)
                        let fy: Float = (Float(iy) + 0.5) / Float(steps.y)
                        let fz: Float = (Float(iz) + 0.5) / Float(steps.z)
                        let unit = SIMD3<Float>(fx * 2 - 1, fy * 2 - 1, fz * 2 - 1)
                        let local: SIMD3<Float> = unit * span
                        // FlowField answers in Float; the free-stream
                        // reference arrives as Double. Mixing them in
                        // one expression is what stalled the type
                        // checker, so every step names its type.
                        let velocity: SIMD3<Float> = field.velocity(at: SIMD3<Double>(local))
                        let speed: Float = simd_length(velocity)
                        guard speed > 1e-4 else { continue }
                        let direction: SIMD3<Float> = velocity / speed
                        // Against free-stream: 1 means "moving as fast
                        // as the wind you dialled in".
                        let ratio: Float = speed / reference
                        let magnitude: Float = min(ratio, 1.4) / 1.4
                        samples.append(FrozenVectors.Sample(
                            position: local,
                            direction: direction,
                            magnitude01: magnitude,
                            kind: .velocity))
                    }
                }
            }
            return samples
        }

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
        // Independent of the solve: the blend clock advances every frame,
        // the two newest fields are materialised into ONE blended field,
        // and the visuals are rebuilt from it at display rate — smoke on
        // the main thread (cheap), ribbons on a worker.
        fieldElapsed += scaledDt
        fieldBlend = Float(min(fieldElapsed / fieldInterval, 1))
        rebuildBlendedField()
        advanceSmoke(dt: scaledDt, model: model)
        submitRibbons(model: model)
    }

    // MARK: Smoke — advected per frame on the blended field

    /// Materialises previous→current at today's blend into one field.
    /// 33k SIMD lerps is a fraction of a millisecond; doing it once here
    /// means every subsequent sample touches a single field.
    private func rebuildBlendedField() {
        guard let current = currentField else { blendedField = nil; return }
        guard fieldBlend < 1, let previous = previousField,
              previous.cells.count == current.cells.count else {
            blendedField = current
            return
        }
        let count = current.cells.count
        var scratch = blendUseA ? blendScratchA : blendScratchB
        if scratch.count != count {
            scratch = [SIMD3<Float>](repeating: .zero, count: count)
        }
        let t = fieldBlend
        previous.cells.withUnsafeBufferPointer { old in
            current.cells.withUnsafeBufferPointer { new in
                scratch.withUnsafeMutableBufferPointer { out in
                    for index in 0..<count {
                        out[index] = old[index] + (new[index] - old[index]) * t
                    }
                }
            }
        }
        if blendUseA { blendScratchA = scratch } else { blendScratchB = scratch }
        blendUseA.toggle()
        blendedField = FlowField(nx: current.nx, ny: current.ny, nz: current.nz,
                                 h: current.h, origin: current.origin,
                                 cells: scratch, solid: current.solid)
    }

    @inline(__always)
    private func flowVelocity(at point: SIMD3<Double>) -> SIMD3<Double> {
        guard let field = blendedField else { return .zero }
        return SIMD3<Double>(field.velocity(at: point))
    }

    private func advanceSmoke(dt: Double, model: WindTunnelModel) {
        guard let mesh = smokeMesh else { return }
        guard model.showParticles, let field = blendedField else {
            mesh.clear()
            return
        }
        if smoke.count != Self.smokeCount {
            smoke = (0..<Self.smokeCount).map { _ in Self.randomInletPoint() }
            smokeAge = (0..<Self.smokeCount).map { _ in Double.random(in: 0..<Self.smokeLife) }
        }

        let (lo, hi) = field.bounds
        let margin = field.h
        smokeScratch.removeAll(keepingCapacity: true)
        smokeScratch.reserveCapacity(Self.smokeCount * 20)

        for index in smoke.indices {
            var p = smoke[index]
            p += flowVelocity(at: p) * dt
            smokeAge[index] += dt
            if p.x > hi.x - margin || smokeAge[index] > Self.smokeLife
                || field.isSolid(at: p)
                || p.y < lo.y + margin || p.y > hi.y - margin
                || p.z < lo.z + margin || p.z > hi.z - margin {
                p = Self.randomInletPoint()
                smokeAge[index] = 0
            }
            smoke[index] = p

            // Four corners of a camera-facing puff, tight when young and
            // spreading as it drifts, straight into the vertex stream.
            let age = Float(smokeAge[index] / Self.smokeLife)
            let size = Self.smokeSizeNear + (Self.smokeSizeFar - Self.smokeSizeNear) * age
            let x = Float(p.x), y = Float(p.y), z = Float(p.z)
            smokeScratch += [x - size, y - size, z, 0, 1,
                             x + size, y - size, z, 1, 1,
                             x + size, y + size, z, 1, 0,
                             x - size, y + size, z, 0, 0]
        }
        mesh.update(vertexFloats: smokeScratch, indices: smokeIndices)
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
        // The blend hides the solve cadence completely, so the solve can
        // run at ~15 Hz — a fraction of the CPU of chasing every frame —
        // with zero visible stepping.
        guard !solveInFlight, flowAccumulator > 1.0 / 15.0 else { return }
        let step = min(flowAccumulator, 1.0 / 10.0)
        flowAccumulator = 0
        solveInFlight = true

        let obstacles = solidObstacles(for: model)
        let inflow = model.windSpeed

        Task { [weak self] in
            guard let self else { return }
            await solver.setInflow(inflow)
            await solver.setObstacles(obstacles)
            await solver.primeIfNeeded()
            let snapshot = await solver.advance(dt: step)
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
        // Roll the double buffer: the field we were blending TOWARD
        // becomes the one we blend FROM, and the blend restarts against
        // the measured arrival interval, so the morph always lands just
        // as the next snapshot does.
        previousField = currentField ?? snapshot.field
        currentField = snapshot.field
        fieldInterval = min(max(fieldElapsed, 1.0 / 30.0), 0.3)
        fieldElapsed = 0
        fieldBlend = 0
        fieldVersion &+= 1
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

    // MARK: The pressure skin
    //
    // Pressure ON the body, not just in the smoke.
    //
    // The smoke already encodes it — Cp = 1 − (v/U)² for incompressible
    // flow, so slow smoke is high pressure — but it encodes it in the
    // AIR, centimetres off the surface, where you have to be told what
    // to look at. The thing people want to see is the object: a red band
    // across the nose that is being pushed back, blue over the shoulders
    // where the flow has accelerated and the pressure has dropped, which
    // over a wing is exactly where lift comes from.
    //
    // The skin is built on the body's OWN aerodynamic silhouette — the
    // same overlapping spheres the CFD voxelises into its solid mask —
    // so what is painted is what the solver actually sees. Each vertex
    // samples the solved field along its outward normal and carries a
    // UV into a Cp ramp texture, so the colour is per-pixel smooth and
    // the mesh uploads as one draw.

    private let pressureSkin = ModelEntity()
    private var pressureSkinMaterial: UnlitMaterial?
    private var lastSkinVersion = -1
    /// Latitude/longitude resolution of each silhouette sphere.
    ///
    /// Halved from 12x20. The skin is rebuilt on the MAIN THREAD, and at
    /// the old resolution a nine-sphere body meant ~2,500 vertices each
    /// walking the grid for a pressure sample, plus a MeshResource
    /// generate, every time a solve landed — a dozen times a second. It
    /// is a label on a shape, not the shape itself; this reads the same
    /// and costs a quarter as much.
    private static let skinRings = 8
    private static let skinSegments = 14
    /// The skin never rebuilds faster than this, however often the flow
    /// solve lands. Pressure on a body changes slowly compared to the
    /// smoke; three times a second is plenty and it stops the solver's
    /// arrival rate from driving main-thread mesh work.
    private static let skinMinimumInterval = 1.0 / 3
    private var lastSkinBuild: Double = -1

    private func syncPressureSkin(_ model: WindTunnelModel) {
        pressureSkin.isEnabled = model.showPressureSkin
        guard model.showPressureSkin, let field = blendedField ?? currentField else {
            return
        }
        // Rebuilt only when a fresh solve lands or the body/size changes —
        // never per frame.
        let version = fieldVersion &* 31
            &+ model.testBody.hashValue
            &+ Int(model.cylinderRadius * 1e4)
            &+ Int(model.cylinderCenter.x * 1e4)
        guard version != lastSkinVersion else { return }
        let now = CACurrentMediaTime()
        guard now - lastSkinBuild >= Self.skinMinimumInterval else { return }
        lastSkinBuild = now
        lastSkinVersion = version

        if pressureSkinMaterial == nil {
            var material = UnlitMaterial(color: .white)
            if let texture = Self.pressureRampTexture() {
                material.color = .init(tint: .white, texture: .init(texture))
            }
            // Translucent enough to read as pressure PAINTED ON the body
            // rather than as a set of blobs replacing it — the shape has
            // to stay recognisable, because the shape is the lesson.
            material.blending = .transparent(opacity: 0.58)
            pressureSkinMaterial = material
        }

        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for sphere in skinSpheres(model) {
            let base = UInt32(positions.count)
            for ring in 0...Self.skinRings {
                let phi = Double(ring) / Double(Self.skinRings) * .pi
                for segment in 0...Self.skinSegments {
                    let theta = Double(segment) / Double(Self.skinSegments) * 2 * .pi
                    let normal = SIMD3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                    let point = sphere.center + normal * sphere.radius
                    // Slightly proud of the model so the skin never
                    // z-fights the body it is describing.
                    positions.append(SIMD3<Float>(point + normal * 0.004))
                    let cp = SurfacePressure.coefficient(
                        at: point, normal: normal, in: field,
                        freestream: max(model.windSpeed, 1e-6))
                    uvs.append(SIMD2(Float(SurfacePressure.rampPosition(cp ?? 0)), 0.5))
                }
            }
            let stride = UInt32(Self.skinSegments + 1)
            for ring in 0..<UInt32(Self.skinRings) {
                for segment in 0..<UInt32(Self.skinSegments) {
                    let a = base + ring * stride + segment
                    let b = a + 1, c = a + stride, d = c + 1
                    indices += [a, c, d, a, d, b]
                }
            }
        }

        guard positions.count >= 3, let material = pressureSkinMaterial else {
            pressureSkin.model = nil
            return
        }
        var descriptor = MeshDescriptor(name: "pressure-skin")
        descriptor.positions = MeshBuffer(positions)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            pressureSkin.model = ModelComponent(mesh: mesh, materials: [material])
        }
    }

    /// The spheres the skin is drawn on — the very same silhouette the
    /// solver marks solid, in section-local coordinates.
    private func skinSpheres(_ model: WindTunnelModel)
    -> [(center: SIMD3<Double>, radius: Double)] {
        if model.testBody == .cylinder {
            let radius = model.cylinderRadius
            let halfSpan = min(Double(Self.halfHeight), WindTunnelModel.cylinderSpan / 2)
            var spheres: [(SIMD3<Double>, Double)] = []
            var y = -halfSpan
            while y <= halfSpan {
                spheres.append((SIMD3(model.cylinderCenter.x, y, model.cylinderCenter.y),
                                radius))
                y += radius * 0.75
            }
            return spheres
        }
        return model.bodyObstacles.spheres.map { ($0.center, $0.radius) }
    }

    /// Cp → colour: deep blue at strong suction, neutral at free stream,
    /// hot red at stagnation. The neutral point is pinned at Cp = 0 by
    /// SurfacePressure.rampPosition, so mid-grey always means "nothing
    /// happening here".
    private static func pressureRampTexture() -> TextureResource? {
        let stops: [(Float, Float, Float)] = [
            (0.10, 0.35, 0.95),   // Cp = −span: strong suction
            (0.25, 0.65, 0.95),
            (0.72, 0.74, 0.78),   // Cp = 0: free stream
            (0.97, 0.55, 0.25),
            (0.92, 0.13, 0.10),   // Cp = +1: stagnation
        ]
        let width = 256
        var bytes = [UInt8](repeating: 0, count: width * 4)
        for x in 0..<width {
            let t = Float(x) / Float(width - 1) * Float(stops.count - 1)
            let i = min(Int(t), stops.count - 2)
            let f = t - Float(i)
            let a = stops[i], b = stops[i + 1]
            bytes[x * 4 + 0] = UInt8(max(0, min(255, (a.0 + (b.0 - a.0) * f) * 255)))
            bytes[x * 4 + 1] = UInt8(max(0, min(255, (a.1 + (b.1 - a.1) * f) * 255)))
            bytes[x * 4 + 2] = UInt8(max(0, min(255, (a.2 + (b.2 - a.2) * f) * 255)))
            bytes[x * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent) else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }

    private func render(_ model: WindTunnelModel) {
        syncPressureSkin(model)
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

    // MARK: Streamlines — traced on a worker, uploaded on main

    private nonisolated struct RibbonJob: Sendable {
        var field: FlowField
        var reference: Double
    }
    private nonisolated struct RibbonOutput: Sendable {
        var vertexFloats: [Float]
        var indices: [UInt32]
    }
    private var ribbonPipeline: GeometryPipeline<RibbonJob, RibbonOutput>?

    /// Hands this frame's blended field to the worker. Newest-wins
    /// coalescing means a busy worker just skips to the latest field —
    /// the ribbons can lag the smoke by a frame, which is invisible;
    /// what matters is that the main thread only ever memcpys.
    private func submitRibbons(model: WindTunnelModel) {
        guard let mesh = ribbonMesh else { return }
        guard model.showStreamlines, let field = blendedField else {
            mesh.clear()
            lastRibbonBlend = -1
            return
        }
        // Nothing changed since the last trace (steady state between
        // solves at blend 1): keep the mesh as it is, trace nothing.
        if fieldBlend == lastRibbonBlend, fieldVersion == lastRibbonVersion { return }
        lastRibbonBlend = fieldBlend
        lastRibbonVersion = fieldVersion

        if ribbonPipeline == nil {
            ribbonPipeline = GeometryPipeline(
                compute: { Self.traceRibbons($0) },
                apply: { [weak self] output in
                    self?.ribbonMesh?.update(vertexFloats: output.vertexFloats,
                                             indices: output.indices)
                })
        }
        ribbonPipeline?.submit(RibbonJob(field: field,
                                         reference: max(model.windSpeed, 1e-6)))
    }

    private nonisolated static func traceRibbons(_ job: RibbonJob) -> RibbonOutput {
        let field = job.field
        let (lo, hi) = field.bounds
        let xStart = lo.x + field.h * 0.6
        let maxX = hi.x - field.h

        var vertexFloats = [Float]()
        vertexFloats.reserveCapacity(ribbonVertexCapacity * 5)
        var indices = [UInt32]()
        indices.reserveCapacity(ribbonIndexCapacity)
        var vertexCount: UInt32 = 0

        for height in ribbonHeights {
            for lateral in ribbonLaterals {
                var p = SIMD3(xStart, height, lateral)
                var previousBase: UInt32?
                for _ in 0..<ribbonSteps {
                    let v = SIMD3<Double>(field.velocity(at: p))
                    let speed = simd_length(v)
                    guard speed > 1e-5 else { break }
                    let tangent = v / speed
                    var side = simd_cross(tangent, SIMD3<Double>(0, 0, 1))
                    let sideLength = simd_length(side)
                    side = sideLength > 1e-6 ? side / sideLength : SIMD3(0, 1, 0)
                    let half = side * ribbonHalfWidth

                    let u = Float(min(max(speed / job.reference - 0.35, 0), 1))
                    let a = p - half, b = p + half
                    vertexFloats += [Float(a.x), Float(a.y), Float(a.z), u, 0.5,
                                     Float(b.x), Float(b.y), Float(b.z), u, 0.5]
                    let base = vertexCount
                    vertexCount += 2
                    if let previous = previousBase {
                        indices += [previous, previous + 1, base + 1,
                                    previous, base + 1, base]
                    }
                    previousBase = base

                    let mid = p + tangent * (ribbonStride * 0.5)
                    let v2 = SIMD3<Double>(field.velocity(at: mid))
                    let s2 = simd_length(v2)
                    p += (s2 > 1e-6 ? v2 / s2 : tangent) * ribbonStride
                    if p.x > maxX || field.isSolid(at: p) { break }
                }
            }
        }
        return RibbonOutput(vertexFloats: vertexFloats, indices: indices)
    }

    private static func makeRibbonMaterial() -> UnlitMaterial {
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: 0.8)
        if let texture = rampTexture() {
            material.color = .init(tint: .white, texture: .init(texture))
        }
        return material
    }

    /// The smoke palette baked into a 256x1 ramp: warm where the air
    /// piles up and slows, near-white in the free stream, cool where it
    /// accelerates around a shoulder.
    private static func rampTexture() -> TextureResource? {
        let width = 256
        var bytes = [UInt8](repeating: 0, count: width * 4)
        for x in 0..<width {
            let t = Float(x) / Float(width - 1) * Float(streamlineColors.count - 1)
            let i = min(Int(t), streamlineColors.count - 2)
            let f = CGFloat(t - Float(i))
            var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            streamlineColors[i].getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
            streamlineColors[i + 1].getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            bytes[x * 4 + 0] = UInt8(max(0, min(255, (r0 + (r1 - r0) * f) * 255)))
            bytes[x * 4 + 1] = UInt8(max(0, min(255, (g0 + (g1 - g0) * f) * 255)))
            bytes[x * 4 + 2] = UInt8(max(0, min(255, (b0 + (b1 - b0) * f) * 255)))
            bytes[x * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent) else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }
}


/// A fixed-capacity mesh whose vertex bytes are rewritten in place every
/// frame via LowLevelMesh. Creating a MeshResource per frame (generate)
/// allocates, re-uploads, and rebuilds bounds 60+ times a second for two
/// meshes — THE main-thread cost the profiler pointed at. This writes
/// straight into RealityKit's buffer instead: zero allocation, one copy.
/// Layout: position float3 + uv float2, 20 bytes per vertex.
@MainActor
final class DynamicMesh {
    let resource: MeshResource
    private let mesh: LowLevelMesh
    private let vertexCapacity: Int
    private let indexCapacity: Int
    private let bounds: BoundingBox
    private static let stride = MemoryLayout<Float>.stride * 5

    init?(vertexCapacity: Int, indexCapacity: Int, bounds: BoundingBox) {
        self.vertexCapacity = vertexCapacity
        self.indexCapacity = indexCapacity
        self.bounds = bounds
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = vertexCapacity
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
            .init(semantic: .uv0, format: .float2, layoutIndex: 0, offset: 12),
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferOffset: 0,
                                          bufferStride: Self.stride)]
        descriptor.indexCapacity = indexCapacity
        descriptor.indexType = .uint32
        guard let mesh = try? LowLevelMesh(descriptor: descriptor),
              let resource = try? MeshResource(from: mesh) else { return nil }
        self.mesh = mesh
        self.resource = resource
        clear()
    }

    /// The triangle list as it was last written to the GPU.
    private var lastIndices: [UInt32] = []
    private var lastPartIndexCount = -1

    /// Rewrites the drawn geometry: 5 floats per vertex, triangle indices.
    ///
    /// Opening each buffer is NOT free, and the profiler is unambiguous
    /// about it: a sample of the wind tunnel put the entire main thread
    /// inside this function, under `recreatePayloadIfNecessary` — every
    /// `withUnsafeMutableBytes` makes RealityKit swap the mesh payload,
    /// with the malloc, free, and asset-map teardown that implies. The
    /// buffers here are small (4,600 vertices); it is the per-OPENING
    /// cost that hurts, and this used to pay it twice a frame.
    ///
    /// Half of that was for nothing. Smoke is a fixed quad list — the
    /// same 3,120 indices, rebuilt identically 90 times a second — and
    /// the streamline topology only changes when a filament starts or
    /// stops. Comparing the arrays first costs a memcmp over 18 KB and
    /// skips a payload swap whenever the answer is "the same as before",
    /// which for the triangles is nearly always.
    func update(vertexFloats: [Float], indices: [UInt32]) {
        let vertexCount = min(vertexFloats.count / 5, vertexCapacity)
        let indexCount = min(indices.count, indexCapacity)
        guard vertexCount > 0, indexCount > 0 else { clear(); return }

        // Positions genuinely change every frame; this one always runs.
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            vertexFloats.withUnsafeBytes { src in
                raw.copyMemory(from: UnsafeRawBufferPointer(
                    start: src.baseAddress, count: vertexCount * Self.stride))
            }
        }

        if lastIndices.count != indexCount
            || !lastIndices.withUnsafeBytes({ old in
                indices.withUnsafeBytes { new in
                    memcmp(old.baseAddress, new.baseAddress,
                           indexCount * MemoryLayout<UInt32>.stride) == 0
                }
            }) {
            mesh.withUnsafeMutableIndices { raw in
                indices.withUnsafeBytes { src in
                    raw.copyMemory(from: UnsafeRawBufferPointer(
                        start: src.baseAddress,
                        count: indexCount * MemoryLayout<UInt32>.stride))
                }
            }
            lastIndices = Array(indices.prefix(indexCount))
        }

        // The part describes how much of the buffer to draw. Re-stating
        // an unchanged one still churns the asset tracker.
        if lastPartIndexCount != indexCount {
            lastPartIndexCount = indexCount
            mesh.parts.replaceAll([
                LowLevelMesh.Part(indexCount: indexCount, topology: .triangle,
                                  bounds: bounds)
            ])
        }
    }

    /// Draw nothing (kept allocated; showing again is just an update).
    func clear() {
        guard lastPartIndexCount != 0 else { return }
        lastPartIndexCount = 0
        mesh.parts.replaceAll([])
    }
}
