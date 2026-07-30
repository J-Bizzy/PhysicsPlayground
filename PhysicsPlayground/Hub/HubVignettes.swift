//
//  HubVignettes.swift
//  Physics Playground — Hub
//
//  The nine miniatures in the hub gallery, and what each of them DOES.
//
//  They used to come from nine Blender assets authored months apart, in
//  nine different styles and at nine different levels of finish — a
//  spiky ball for the electric field, a stack of coloured tiles for the
//  drumhead — and they were static. Worse, the "live exhibit" animation
//  added later matched children by NAME, and those names only existed in
//  the procedural fallbacks; every module that loaded an asset silently
//  never animated at all.
//
//  So: one file, nine models, built to one visual language, each
//  returning its own animation closure alongside the geometry it drives.
//  A model and its motion can no longer drift apart, because they are
//  written in the same place and the closure captures the very entities
//  it moves — no name lookups, no per-frame tree searches.
//
//  Every miniature is authored inside a half-extent of about 8.5 cm so
//  it sits inside its card with room for the name, and every one of them
//  is doing the thing its module is about: the pendulums beat against
//  each other, the ripples interfere, the electrons go round the loop,
//  the drumhead stands in a mode.
//

import Foundation
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
enum HubVignettes {
    /// A miniature and the per-frame animation that brings it to life.
    struct Built {
        let entity: Entity
        /// Called every frame with the elapsed time, in seconds.
        let animate: (Double) -> Void
    }

    /// The apparent half-height every miniature is authored to.
    static let half: Float = 0.085

    static func make(for moduleID: String) -> Built {
        switch moduleID {
        case "electrostatics": fields()
        case "kinematics": projectile()
        case "gravitylab": gravity()
        case "windtunnel": windTunnel()
        case "circuits": circuits()
        case "pendulums": pendulums()
        case "magnetism": magnetism()
        default: fallback()
        }
    }

    // MARK: Shared parts

    private static func ball(_ radius: Float, _ color: UIColor,
                             glow: Float = 0.45) -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: radius),
                    materials: [Materials.energized(color, glow: glow)])
    }

    private static func rod(length: Float, radius: Float, _ color: UIColor,
                            glow: Float = 0.2) -> ModelEntity {
        ModelEntity(mesh: .generateCylinder(height: length, radius: radius),
                    materials: [Materials.energized(color, glow: glow)])
    }

    private static func line(_ points: [SIMD3<Float>], radius: Float,
                             _ color: UIColor, opacity: Float = 1) -> ModelEntity? {
        guard let mesh = TubeMesh.tube(lines: [points], radius: radius, sides: 5) else {
            return nil
        }
        var material = UnlitMaterial(color: color)
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private static func ring(radius: Float, tube: Float, _ color: UIColor,
                             opacity: Float = 1, segments: Int = 40) -> ModelEntity? {
        let points = (0...segments).map { step -> SIMD3<Float> in
            let angle = Float(step) / Float(segments) * 2 * .pi
            return SIMD3(cos(angle) * radius, 0, sin(angle) * radius)
        }
        return line(points, radius: tube, color, opacity: opacity)
    }

    // MARK: Fields — a dipole breathing

    private static func fields() -> Built {
        // An inner frame the breathing scale writes to.
        //
        // The animation used to scale the ROOT — which is the very
        // entity every caller fits to its slot, so the fit was silently
        // overwritten sixty times a second and this exhibit came out a
        // different size from all the others. A vignette must never
        // touch its own root transform; that belongs to whoever placed
        // it.
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)
        let positive = ball(0.020, DesignTokens.Palette.positiveUI, glow: 0.6)
        let negative = ball(0.020, DesignTokens.Palette.negativeUI, glow: 0.6)
        frame.addChild(positive)
        frame.addChild(negative)

        // The signs, so a glance says "dipole" and not "two dots".
        let barMesh = MeshResource.generateBox(size: [0.017, 0.004, 0.004],
                                               cornerRadius: 0.002)
        let signMaterial = UnlitMaterial(color: .white)
        for (parent, vertical) in [(positive, true), (negative, false)] {
            let across = ModelEntity(mesh: barMesh, materials: [signMaterial])
            across.position.z = 0.019
            parent.addChild(across)
            if vertical {
                let up = ModelEntity(mesh: barMesh, materials: [signMaterial])
                up.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                up.position.z = 0.019
                parent.addChild(up)
            }
        }

        // Field lines: arcs from + to −, fanned around the axis.
        var arcs: [ModelEntity] = []
        let separation: Float = 0.048
        for turn in 0..<4 {
            let roll = Float(turn) / 4 * .pi
            let points = (0...26).map { step -> SIMD3<Float> in
                let t = Float(step) / 26
                let angle = t * .pi
                let bulge = sin(angle) * 0.062
                let x = -separation * cos(angle)
                return SIMD3(x, bulge * cos(roll), bulge * sin(roll))
            }
            if let arc = line(points, radius: 0.0022,
                              DesignTokens.Palette.fieldLineUI, opacity: 0.9) {
                frame.addChild(arc)
                arcs.append(arc)
            }
        }

        return Built(entity: root) { time in
            // The pair eases apart and back; the lines answer by
            // brightening as the charges close.
            let breath = Float(sin(time * 0.9))
            let gap = separation * (1 + 0.16 * breath)
            positive.position.x = -gap
            negative.position.x = gap
            frame.scale = SIMD3(repeating: separation / max(gap, 1e-4))
            for (index, arc) in arcs.enumerated() {
                let phase = Float(sin(time * 1.6 + Double(index) * 0.7))
                arc.components.set(OpacityComponent(opacity: 0.55 + 0.45 * phase * phase))
            }
        }
    }

    // MARK: Projectile — a ball through a hoop, on a loop

    private static func projectile() -> Built {
        let root = Entity()

        // The launcher: a stubby barrel on a base, aimed up the arc.
        let base = ball(0.012, DesignTokens.Palette.launcherUI, glow: 0)
        base.position = [-0.075, -0.05, 0]
        root.addChild(base)
        let barrel = rod(length: 0.042, radius: 0.008,
                         DesignTokens.Palette.launcherUI, glow: 0.05)
        barrel.orientation = simd_quatf(angle: -.pi / 4, axis: [0, 0, 1])
        barrel.position = [-0.061, -0.036, 0]
        root.addChild(barrel)

        // The hoop it is aimed at.
        let hoopRadius: Float = 0.022
        if let hoop = ring(radius: hoopRadius, tube: 0.0035,
                           UIColor(red: 0.35, green: 0.95, blue: 0.6, alpha: 1)) {
            hoop.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            hoop.position = [0.062, -0.012, 0]
            root.addChild(hoop)
        }

        /// The flight, as a real parabola from the muzzle to the hoop.
        func flight(_ t: Float) -> SIMD3<Float> {
            let start = SIMD3<Float>(-0.055, -0.03, 0)
            let end = SIMD3<Float>(0.062, -0.012, 0)
            let apex: Float = 0.075
            let position = start + (end - start) * t
            return SIMD3(position.x, position.y + apex * 4 * t * (1 - t), 0)
        }

        // Strobe dots: equal steps in TIME, so their spacing tells the
        // story — even across, bunching at the top.
        var dots: [ModelEntity] = []
        let dotCount = 9
        for _ in 0..<dotCount {
            let dot = ModelEntity(
                mesh: .generateSphere(radius: 0.0042),
                materials: [Materials.energized(
                    DesignTokens.Palette.projectileUI, glow: 0.7)])
            root.addChild(dot)
            dots.append(dot)
        }
        let ballEntity = ball(0.0095, DesignTokens.Palette.projectileUI, glow: 0.55)
        root.addChild(ballEntity)

        return Built(entity: root) { time in
            let period = 2.6
            let t = Float((time.truncatingRemainder(dividingBy: period)) / period)
            ballEntity.position = flight(t)
            // The trail fills in behind the ball and clears on each throw.
            for (index, dot) in dots.enumerated() {
                let at = Float(index + 1) / Float(dotCount + 1)
                dot.position = flight(at)
                let shown = at < t
                dot.components.set(OpacityComponent(
                    opacity: shown ? 0.25 + 0.55 * (1 - (t - at)) : 0))
            }
        }
    }

    // MARK: Gravity — a sun and two planets on inclined orbits

    private static func gravity() -> Built {
        let root = Entity()

        let sun = ball(0.021, DesignTokens.Palette.celestialUI("Sun"), glow: 1.0)
        root.addChild(sun)
        var coronaMaterial = UnlitMaterial(color: DesignTokens.Palette.celestialUI("Sun"))
        coronaMaterial.blending = .transparent(opacity: 0.22)
        let corona = ModelEntity(mesh: .generateSphere(radius: 0.032),
                                 materials: [coronaMaterial])
        root.addChild(corona)

        struct Orbit { let pivot: Entity; let planet: Entity; let rate: Double }
        var orbits: [Orbit] = []
        let plan: [(radius: Float, tilt: Float, rate: Double, name: String, size: Float)] = [
            (0.048, 0.20, 1.00, "Earth", 0.0085),
            (0.076, -0.42, 0.58, "Mars", 0.0068),
        ]
        for spec in plan {
            let pivot = Entity()
            pivot.orientation = simd_quatf(angle: spec.tilt, axis: [1, 0, 0])
            root.addChild(pivot)
            if let path = ring(radius: spec.radius, tube: 0.0012, .white, opacity: 0.3) {
                pivot.addChild(path)
            }
            let carrier = Entity()
            pivot.addChild(carrier)
            let planet = ball(spec.size, DesignTokens.Palette.celestialUI(spec.name), glow: 0.2)
            planet.position = [spec.radius, 0, 0]
            carrier.addChild(planet)
            orbits.append(Orbit(pivot: carrier, planet: planet, rate: spec.rate))
        }

        return Built(entity: root) { time in
            for orbit in orbits {
                orbit.pivot.orientation = simd_quatf(
                    angle: Float(time * orbit.rate), axis: [0, 1, 0])
            }
            // The star breathes, the way a light source should.
            let pulse = 1 + 0.05 * Float(sin(time * 1.3))
            corona.scale = SIMD3(repeating: pulse)
        }
    }

    // MARK: Waves — two sources interfering

    private static func waves() -> Built {
        let root = Entity()
        let centres: [SIMD3<Float>] = [[-0.038, 0, 0], [0.038, 0, 0]]
        var ripples: [(entity: ModelEntity, offset: Double)] = []

        // Rings are built at their FINAL radii, not built once and
        // scaled. Scaling a swept tube scales its cross-section too, so
        // a ring grown from 0.008 to 0.09 thins its own line by a factor
        // of eleven and disappears — which is exactly what happened.
        // Fixed radii with a travelling brightness reads as an expanding
        // crest and keeps every line the same weight.
        let radii: [Float] = [0.017, 0.033, 0.049, 0.065, 0.081]

        for centre in centres {
            let puck = ModelEntity(
                mesh: .generateCylinder(height: 0.007, radius: 0.010),
                materials: [Materials.energized(
                    DesignTokens.Palette.waveSourceUI, glow: 0.7)])
            puck.position = centre
            root.addChild(puck)

            for (step, radius) in radii.enumerated() {
                guard let wave = ring(radius: radius, tube: 0.0016,
                                      DesignTokens.Palette.waveSourceUI)
                else { continue }
                wave.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                wave.position = centre
                root.addChild(wave)
                ripples.append((wave, Double(step) / Double(radii.count)))
            }
        }

        return Built(entity: root) { time in
            for ripple in ripples {
                // Brightness travels outward through the fixed rings.
                let phase = (time * 0.6 - ripple.offset)
                    .truncatingRemainder(dividingBy: 1)
                let wrapped = phase < 0 ? phase + 1 : phase
                ripple.entity.components.set(
                    OpacityComponent(opacity: Float(1 - wrapped) * 0.9))
            }
        }
    }

    // MARK: Wind tunnel — a fan, a body, and flow going past it

    private static func windTunnel() -> Built {
        let root = Entity()

        // The fan: a ring with blades that actually turn.
        let fanX: Float = -0.070
        if let guard1 = ring(radius: 0.030, tube: 0.0035,
                             UIColor(red: 0.95, green: 0.85, blue: 0.3, alpha: 1)) {
            guard1.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            guard1.position.x = fanX
            root.addChild(guard1)
        }
        let blades = Entity()
        blades.position.x = fanX
        root.addChild(blades)
        let bladeMesh = MeshResource.generateBox(size: [0.003, 0.024, 0.010],
                                                 cornerRadius: 0.0015)
        for index in 0..<5 {
            let blade = ModelEntity(
                mesh: bladeMesh,
                materials: [Materials.energized(UIColor(white: 0.72, alpha: 1),
                                                metallic: 1, glow: 0)])
            let angle = Float(index) / 5 * 2 * .pi
            blade.orientation = simd_quatf(angle: angle, axis: [1, 0, 0])
            blade.position = [0, cos(angle) * 0.014, sin(angle) * 0.014]
            blades.addChild(blade)
        }

        // The test body: a teardrop, nose into the wind.
        let body = ModelEntity(
            mesh: .generateSphere(radius: 0.017),
            materials: [Materials.energized(
                UIColor(red: 0.85, green: 0.28, blue: 0.20, alpha: 1), glow: 0.15)])
        body.scale = [1.7, 0.85, 0.85]
        body.position = [0.024, 0, 0]
        root.addChild(body)

        // Filaments that part around it — the shape of the flow, and
        // they travel, so the tunnel is visibly running.
        var filaments: [(entity: ModelEntity, offset: Float)] = []
        for lane in [-0.030, -0.014, 0.014, 0.030] as [Float] {
            let points = (0...24).map { step -> SIMD3<Float> in
                let t = Float(step) / 24
                let x = -0.048 + t * 0.128
                // Push aside near the body, close again behind it.
                let bulge = exp(-pow((x - 0.024) / 0.030, 2)) * 0.020
                let sign: Float = lane > 0 ? 1 : -1
                let scale = 0.030 / max(abs(lane), 0.014)
                return SIMD3(x, lane + sign * bulge / scale, 0)
            }
            guard let filament = line(points, radius: 0.0014,
                                      UIColor(red: 0.25, green: 0.6, blue: 0.95, alpha: 1),
                                      opacity: 0.85) else { continue }
            root.addChild(filament)
            filaments.append((filament, abs(lane)))
        }

        return Built(entity: root) { time in
            blades.orientation = simd_quatf(angle: Float(time * 5.5), axis: [1, 0, 0])
            // The filaments shimmer along their length, reading as flow.
            for filament in filaments {
                let phase = Float(sin(time * 3.4 - Double(filament.offset) * 20))
                filament.entity.components.set(
                    OpacityComponent(opacity: 0.55 + 0.35 * phase * phase))
            }
        }
    }

    // MARK: Circuits — a lit loop with charge going round it

    private static func circuits() -> Built {
        let root = Entity()

        // A rounded rectangular loop of wire, and the parts sitting on it.
        let width: Float = 0.062, height: Float = 0.040
        let corners: [SIMD3<Float>] = (0...48).map { step in
            let t = Float(step) / 48 * 2 * .pi
            // Superellipse: a rectangle with soft corners, in one line.
            let cx = cos(t), sy = sin(t)
            return SIMD3(width * sign(cx) * pow(abs(cx), 0.55),
                         height * sign(sy) * pow(abs(sy), 0.55), 0)
        }
        if let wire = line(corners, radius: 0.0026,
                           UIColor(white: 0.10, alpha: 1)) {
            root.addChild(wire)
        }

        let battery = ModelEntity(
            mesh: .generateBox(size: [0.030, 0.014, 0.014], cornerRadius: 0.004),
            materials: [Materials.energized(
                UIColor(red: 0.24, green: 0.42, blue: 0.28, alpha: 1),
                metallic: 0.7, glow: 0)])
        battery.position = [0, -height, 0]
        root.addChild(battery)

        let bulb = ball(0.013, UIColor(red: 1.0, green: 0.87, blue: 0.45, alpha: 1), glow: 1)
        bulb.position = [0, height, 0]
        root.addChild(bulb)
        var haloMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.88, blue: 0.5, alpha: 1))
        haloMaterial.blending = .transparent(opacity: 0.25)
        let halo = ModelEntity(mesh: .generateSphere(radius: 0.023),
                               materials: [haloMaterial])
        halo.position = [0, height, 0]
        root.addChild(halo)

        // Charge carriers, evenly spaced round the loop.
        var carriers: [ModelEntity] = []
        for _ in 0..<10 {
            let dot = ModelEntity(
                mesh: .generateSphere(radius: 0.0032),
                materials: [Materials.energized(
                    DesignTokens.Palette.electronUI, glow: 0.9)])
            root.addChild(dot)
            carriers.append(dot)
        }

        func onLoop(_ t: Float) -> SIMD3<Float> {
            let angle = t * 2 * .pi
            let cx = cos(angle), sy = sin(angle)
            return SIMD3(width * sign(cx) * pow(abs(cx), 0.55),
                         height * sign(sy) * pow(abs(sy), 0.55), 0)
        }

        return Built(entity: root) { time in
            for (index, carrier) in carriers.enumerated() {
                let t = Float((time * 0.18 + Double(index) / Double(carriers.count))
                    .truncatingRemainder(dividingBy: 1))
                carrier.position = onLoop(t)
            }
            // The filament breathes as if the supply were alive.
            let glow = 0.75 + 0.25 * Float(sin(time * 2.1))
            halo.scale = SIMD3(repeating: 0.85 + glow * 0.3)
            halo.components.set(OpacityComponent(opacity: glow * 0.55))
        }
    }

    // MARK: Oscillators — pendulums beating, and a spring

    private static func pendulums() -> Built {
        let root = Entity()

        let beam = ModelEntity(
            mesh: .generateBox(size: [0.13, 0.006, 0.010], cornerRadius: 0.003),
            materials: [Materials.energized(UIColor(white: 0.62, alpha: 1),
                                            metallic: 1, glow: 0)])
        beam.position.y = 0.070
        root.addChild(beam)

        // Three lengths a few per cent apart: they leave together, drift
        // out of step and re-align — the module's whole point, in a
        // miniature you can read in a second.
        struct Swing { let pivot: Entity; let period: Double }
        var swings: [Swing] = []
        for (index, length) in [Float(0.052), 0.060, 0.069].enumerated() {
            let pivot = Entity()
            pivot.position = [(Float(index) - 1) * 0.040, 0.067, 0]
            root.addChild(pivot)
            if let cable = line([[0, 0, 0], [0, -length, 0]], radius: 0.0011,
                                UIColor(white: 0.25, alpha: 1)) {
                pivot.addChild(cable)
            }
            let bob = ball(0.010, DesignTokens.Palette.pendulumsAccentUI, glow: 0.15)
            bob.position.y = -length
            pivot.addChild(bob)
            // Real pendulum timing: T grows as the square root of length.
            swings.append(Swing(pivot: pivot, period: Double(length.squareRoot()) * 6.2))
        }

        return Built(entity: root) { time in
            for swing in swings {
                let angle = 0.42 * sin(2 * .pi * time / swing.period)
                swing.pivot.orientation = simd_quatf(angle: Float(angle), axis: [0, 0, 1])
            }
        }
    }

    // MARK: Springs — a block on a rail, its coil breathing

    private static func springs() -> Built {
        let root = Entity()

        // Anchor post, rail, block — the single-spring bench in essence.
        let post = ModelEntity(
            mesh: .generateBox(size: [0.008, 0.052, 0.02], cornerRadius: 0.003),
            materials: [Materials.energized(UIColor(white: 0.5, alpha: 1),
                                            metallic: 1, glow: 0)])
        post.position.x = -0.058
        root.addChild(post)

        let rail = rod(length: 0.116, radius: 0.0016, UIColor(white: 0.55, alpha: 1))
        rail.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        rail.position.y = -0.012
        root.addChild(rail)

        let block = ModelEntity(
            mesh: .generateBox(size: [0.020, 0.020, 0.020], cornerRadius: 0.004),
            materials: [Materials.energized(DesignTokens.Palette.springsAccentUI,
                                            metallic: 0.6, glow: 0.15)])
        root.addChild(block)

        // A real helix, stretched along its axis by the block's motion.
        //
        // Authored at its RESTING length, not at unit length: a model
        // built a metre long and scaled down at runtime reports
        // metre-sized bounds to anything that measures it, and the
        // exhibit fit does measure it.
        let coilRest: Float = 0.044
        let coilPoints = (0...60).map { step -> SIMD3<Float> in
            let t = Float(step) / 60
            let angle = t * 7 * 2 * .pi
            return SIMD3(t * coilRest, cos(angle) * 0.008, sin(angle) * 0.008)
        }
        let coil = line(coilPoints, radius: 0.0012, UIColor(white: 0.78, alpha: 1))
        coil.map { entity in
            entity.position = [-0.054, 0, 0]
            root.addChild(entity)
        }

        return Built(entity: root) { time in
            // Simple harmonic motion, read straight off the clock.
            let x = Float(0.026 * sin(time * 2.3))
            block.position.x = 0.002 + x
            // The coil stretches to exactly reach the block's near face.
            coil?.scale.x = (block.position.x + 0.054 - 0.010) / coilRest
        }
    }

    // MARK: Magnetism — two bar magnets, forever almost snapping

    private static func magnetism() -> Built {
        let root = Entity()

        /// A bar magnet: red north half, blue south half, end to end.
        func magnet() -> Entity {
            let bar = Entity()
            let half = MeshResource.generateBox(size: [0.026, 0.014, 0.014],
                                                cornerRadius: 0.002)
            let north = ModelEntity(mesh: half, materials: [
                Materials.energized(UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1),
                                    glow: 0.25)])
            north.position.x = -0.013
            let south = ModelEntity(mesh: half, materials: [
                Materials.energized(UIColor(red: 0.25, green: 0.47, blue: 0.95, alpha: 1),
                                    glow: 0.25)])
            south.position.x = 0.013
            bar.addChild(north)
            bar.addChild(south)
            return bar
        }

        let left = magnet()
        let right = magnet()
        // Authored at the WIDEST pose, for the same reason the spring
        // coil is authored at its resting length: the exhibit fit
        // measures bounds at build time, before any animation has run.
        // Left at the origin, these two measured as ONE magnet wide, the
        // fit scaled the vignette up 5×, and the swinging magnets
        // trespassed into the neighbouring exhibit.
        left.position.x = -0.055
        right.position.x = 0.055
        root.addChild(left)
        root.addChild(right)

        // Field loops threading the gap between the facing poles —
        // brightening as the magnets close, the pull made visible.
        var loops: [ModelEntity] = []
        for (radius, tilt) in [(Float(0.020), Float(0)),
                               (0.034, .pi / 5), (0.034, -.pi / 5)] {
            let points = (0...30).map { step -> SIMD3<Float> in
                let angle = Float(step) / 30 * 2 * .pi
                return SIMD3(sin(tilt) * radius * sin(angle),
                             radius * cos(angle),
                             cos(tilt) * radius * sin(angle))
            }
            if let loop = line(points, radius: 0.0018,
                               DesignTokens.Palette.fieldLineUI, opacity: 0.8) {
                root.addChild(loop)
                loops.append(loop)
            }
        }

        return Built(entity: root) { time in
            // The approach, the almost-snap, the ease apart — the pull
            // between opposite poles as a loop of motion. The gap never
            // quite closes: a snap that lands would need a jolt, and a
            // jolt on a loop reads as a glitch.
            let breath = Float((1 + sin(time * 1.1)) / 2)   // 0…1
            let gap = 0.020 + 0.038 * (1 - breath)
            left.position.x = -0.026 - gap / 2
            right.position.x = 0.026 + gap / 2
            for (index, loop) in loops.enumerated() {
                loop.components.set(OpacityComponent(
                    opacity: 0.25 + 0.6 * breath - Float(index) * 0.08))
                loop.scale = SIMD3(repeating: 1 + gap * 3)
            }
        }
    }

    // MARK: Elastic field — a drumhead standing in a mode

    private static func elasticField() -> Built {
        let root = Entity()
        let side = 7
        let span: Float = 0.155
        let step = span / Float(side - 1)
        let tile = MeshResource.generateBox(size: [step * 0.80, step * 0.80, 0.006],
                                            cornerRadius: 0.002)
        var cells: [(entity: ModelEntity, amplitude: Float)] = []

        for j in 0..<side {
            for i in 0..<side {
                let u = Float(i) / Float(side - 1)
                let v = Float(j) / Float(side - 1)
                // A (2,2) standing mode: four cells, nodal lines between.
                let amplitude = sin(2 * .pi * u) * sin(2 * .pi * v) * 0.040
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: UIColor(
                    red: CGFloat(0.30 + 0.62 * abs(amplitude) / 0.040),
                    green: 0.74, blue: CGFloat(0.88 - 0.5 * abs(amplitude) / 0.040),
                    alpha: 1))
                material.roughness = 0.35
                material.emissiveColor = .init(color: .white)
                material.emissiveIntensity = 0.12
                let cell = ModelEntity(mesh: tile, materials: [material])
                cell.position = SIMD3(-span / 2 + Float(i) * step,
                                      -span / 2 + Float(j) * step, 0)
                root.addChild(cell)
                cells.append((cell, amplitude))
            }
        }
        // Leaning back, like the real drumhead — a plate facing you
        // square shows none of its relief.
        root.orientation = simd_quatf(angle: -0.34, axis: [1, 0, 0])

        return Built(entity: root) { time in
            let phase = Float(sin(time * 2.4))
            for cell in cells {
                cell.entity.position.z = cell.amplitude * phase
            }
        }
    }

    // MARK: Optics — a beam brought to a focus

    private static func optics() -> Built {
        let root = Entity()

        // A biconvex lens: two shallow spherical caps, as glass.
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: UIColor(red: 0.78, green: 0.92, blue: 1, alpha: 1))
        glass.roughness = 0.04
        glass.clearcoat = .init(floatLiteral: 1)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.42))
        let lens = ModelEntity(mesh: .generateSphere(radius: 0.030), materials: [glass])
        lens.scale = [0.22, 1, 1]
        root.addChild(lens)
        if let rim = ring(radius: 0.030, tube: 0.0022,
                          UIColor(red: 0.4, green: 0.8, blue: 1, alpha: 1)) {
            rim.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            root.addChild(rim)
        }

        // Parallel rays in, converging to the focus on the far side.
        let focus = SIMD3<Float>(0.062, 0, 0)
        var rays: [ModelEntity] = []
        for height in [-0.024, -0.012, 0, 0.012, 0.024] as [Float] {
            let points: [SIMD3<Float>] = [
                SIMD3(-0.080, height, 0), SIMD3(0, height, 0), focus,
                focus + (focus - SIMD3(0, height, 0)) * 0.55,
            ]
            guard let ray = line(points, radius: 0.0016,
                                 UIColor(red: 1, green: 0.34, blue: 0.28, alpha: 1),
                                 opacity: 0.9) else { continue }
            root.addChild(ray)
            rays.append(ray)
        }
        let focusDot = ball(0.005, UIColor(red: 1, green: 0.9, blue: 0.6, alpha: 1), glow: 1)
        focusDot.position = focus
        root.addChild(focusDot)

        return Built(entity: root) { time in
            // Light pulses along the rays, so the beam reads as running.
            for (index, ray) in rays.enumerated() {
                let phase = Float(sin(time * 2.6 - Double(index) * 0.5))
                ray.components.set(OpacityComponent(opacity: 0.6 + 0.4 * phase * phase))
            }
            focusDot.scale = SIMD3(repeating: 1 + 0.35 * Float(sin(time * 2.6)))
        }
    }

    // MARK: Fallback — a new module gets something until it has art

    private static func fallback() -> Built {
        let root = Entity()
        let sphere = ball(0.030, UIColor(white: 0.7, alpha: 1), glow: 0.3)
        root.addChild(sphere)
        return Built(entity: root) { time in
            sphere.scale = SIMD3(repeating: 1 + 0.06 * Float(sin(time * 1.4)))
        }
    }
}

/// `sign` for Float without importing anything heavier.
private func sign(_ value: Float) -> Float {
    value < 0 ? -1 : 1
}
