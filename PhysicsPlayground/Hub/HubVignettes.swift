//
//  HubVignettes.swift
//  Physics Playground — Hub
//
//  The lab emblems the home's portals run. Each is one bold object —
//  the charges, the loop, the magnet, the prism, the launcher, the
//  pendulum, the star — built from a few big parts and thick lines, so it reads at twenty-two
//  centimetres across the room. Solid parts load from
//  usdz; lines, arcs and orbits stay procedural. Three rules:
//    1. A vignette NEVER writes its own root transform; content hangs off
//       an inner `frame`.
//    2. `fit` owns `frame.position`/`frame.scale`; an animation needing
//       its own scale gets a third level beneath the frame.
//    3. Every drawn line goes through `lines(_:)` (dark casing, bright core).
//

import Foundation
import PhysicsCore
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
        /// What the miniature's own geometry fills, swept across its whole
        /// cycle — whether what sits inside the square is a picture or a streak.
        let contentExtents: SIMD3<Float>

        init(entity: Entity,
             animate: @escaping (Double) -> Void,
             contentExtents: SIMD3<Float> = .zero) {
            self.entity = entity
            self.animate = animate
            self.contentExtents = contentExtents
        }
    }

    /// The half-extent of the square every miniature is normalised into, so
    /// differently shaped exhibits read as one set whatever a host
    /// divides by.
    static let frameHalf: Float = 0.085

    static func make(for moduleID: String) -> Built {
        switch moduleID {
        case "electrostatics": fields()
        case "circuits": circuits()
        case "magnetism": magnetism()
        case "optics": optics()
        case "kinematics": projectile()
        case "pendulums": pendulums()
        case "gravitylab": gravity()
        default: fallback()
        }
    }

    // MARK: The common frame

    /// Centres `frame` on the root's origin and normalises it to the common
    /// square, sampling a whole cycle of the motion (the resting pose would
    /// overflow mid-swing). `centredOn` picks the point that lands in the
    /// middle.
    private static func fit(root: Entity, frame: Entity,
                            cycle: Double,
                            centredOn pivot: SIMD3<Float>? = nil,
                            animate: @escaping (Double) -> Void) -> Built {
        frame.position = .zero
        frame.scale = .one

        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let samples = 24
        for step in 0..<samples {
            animate(cycle * Double(step) / Double(samples))
            let box = frame.visualBounds(relativeTo: root)
            lower = simd_min(lower, box.min)
            upper = simd_max(upper, box.max)
        }

        // Half-extents measured outward from the centre, larger side —
        // keeps an off-centre anchor's long side inside the square.
        let centre = pivot ?? (lower + upper) / 2
        let reach = simd_max(upper - centre, centre - lower)
        let span = max(reach.x, max(reach.y, 1e-4)) * 2
        let scale = frameHalf * 2 / span
        // The offset is the scaled centre negated (the frame scale applies
        // to the centre just measured).
        frame.scale = SIMD3(repeating: scale)
        frame.position = -centre * scale

        // An invisible square proxy on the root so both hosts measure one
        // pose-independent box.
        let proxy = ModelEntity(
            mesh: Primitives.box(size: [frameHalf * 2, frameHalf * 2, 0.0005]),
            materials: [{
                let clear = Materials.unlit(.white, opacity: 0)
                return clear
            }()])
        proxy.name = "vignette-square"
        proxy.components.set(OpacityComponent(opacity: 0))
        root.addChild(proxy)

        animate(0)
        return Built(entity: root, animate: animate,
                     contentExtents: reach * 2 * scale)
    }

    // MARK: Shared parts

    private static func ball(_ radius: Float, _ color: UIColor,
                             glow: Float = 0.45) -> ModelEntity {
        ModelEntity(mesh: Primitives.sphere(radius: radius),
                    materials: [Materials.energized(color, glow: glow)])
    }

    private static func rod(length: Float, radius: Float, _ color: UIColor,
                            glow: Float = 0.2) -> ModelEntity {
        ModelEntity(mesh: Primitives.cylinder(height: length, radius: radius),
                    materials: [Materials.energized(color, glow: glow)])
    }

    /// A bundle of drawn lines in the two design-system passes (dark casing
    /// under a bright core). All paths share one mesh per pass, so a
    /// sixteen-line bundle is two draw calls.
    private static func lines(_ paths: [[SIMD3<Float>]], radius: Float,
                              _ color: UIColor, opacity: Float = 1) -> Entity? {
        let usable = paths.filter { $0.count > 1 }
        guard !usable.isEmpty,
              let core = TubeMesh.tube(lines: usable, radius: radius, sides: 5),
              let casing = TubeMesh.tube(
                lines: usable,
                radius: Materials.casingRadius(forCore: radius), sides: 5)
        else { return nil }

        let (casingMaterial, coreMaterial) = Materials.contrastLine(color)
        let entity = Entity()
        entity.addChild(ModelEntity(mesh: casing, materials: [casingMaterial]))
        entity.addChild(ModelEntity(mesh: core, materials: [coreMaterial]))
        if opacity < 1 {
            entity.components.set(OpacityComponent(opacity: opacity))
        }
        return entity
    }

    private static func line(_ points: [SIMD3<Float>], radius: Float,
                             _ color: UIColor, opacity: Float = 1) -> Entity? {
        lines([points], radius: radius, color, opacity: opacity)
    }

    private static func ring(radius: Float, tube: Float, _ color: UIColor,
                             opacity: Float = 1, segments: Int = 40) -> Entity? {
        let points = (0...segments).map { step -> SIMD3<Float> in
            let angle = Float(step) / Float(segments) * 2 * .pi
            return SIMD3(cos(angle) * radius, 0, sin(angle) * radius)
        }
        return line(points, radius: tube, color, opacity: opacity)
    }

    // MARK: Modeled props

    /// A prop from the shared `PropCache`, centred on its origin and scaled
    /// so its longest dimension is `longest`. Measured rather than assumed;
    /// every call site keeps its old geometry as the fallback.
    private static func prop(_ name: String, longest: Float) -> Entity? {
        guard let prototype = PropCache.prototype(named: name) else { return nil }

        let model = prototype.clone(recursive: true)
        let box = model.visualBounds(relativeTo: nil)
        let span = max(box.extents.x, max(box.extents.y, box.extents.z))
        guard span > 1e-5 else { return nil }
        let scale = longest / span

        let holder = Entity()
        model.scale = SIMD3(repeating: scale)
        model.position = -box.center * scale
        holder.addChild(model)
        return holder
    }

    // MARK: Worlds

    /// A celestial body wearing the same procedural texture Orbital Mechanics
    /// gives it, falling back to its accent until the texture has been drawn
    /// (`CelestialTextures` renders off the main path).
    private static func celestialMaterial(_ name: String) -> RealityKit.Material {
        let texture = CelestialTextures.texture(for: name)
        if name.hasPrefix("Sun") {
            // Unlit: a star is self-luminous, and at this size a lit
            // sphere with a terminator across it reads as a moon.
            var material = UnlitMaterial(
                color: DesignTokens.Palette.celestialUI(name))
            if let texture {
                material.color = .init(tint: .white, texture: .init(texture))
            }
            return material
        }
        if let texture {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = 0.7
            material.metallic = 0.0
            return material
        }
        return Materials.energized(DesignTokens.Palette.celestialUI(name),
                                   glow: 0.2)
    }

    private static func world(_ name: String, radius: Float) -> ModelEntity {
        ModelEntity(mesh: Primitives.sphere(radius: radius),
                    materials: [celestialMaterial(name)])
    }

    // MARK: Field lines, integrated

    /// A point source of a `1/r²` field: a charge, or one end of a bar
    /// magnet under the magnetic-charge model.
    private struct Pole {
        let at: SIMD3<Float>
        let strength: Float
    }

    private static func fieldDirection(at point: SIMD3<Float>,
                                       poles: [Pole]) -> SIMD3<Float>? {
        var field = SIMD3<Float>.zero
        for pole in poles {
            let offset = point - pole.at
            let distance = simd_length(offset)
            guard distance > 1e-5 else { return nil }
            field += pole.strength * offset / (distance * distance * distance)
        }
        let magnitude = simd_length(field)
        guard magnitude > 1e-9 else { return nil }
        return field / magnitude
    }

    /// One field line, integrated through a set of point sources by midpoint
    /// marching `dr/ds = Ê`. A few thousand multiplies at build time gets the
    /// topology right, including the lines that never close.
    private static func fieldLine(from seed: SIMD3<Float>,
                                  poles: [Pole],
                                  step: Float,
                                  escape: Float,
                                  sinks: [(at: SIMD3<Float>, radius: Float)],
                                  maxSteps: Int = 700) -> [SIMD3<Float>] {
        var point = seed
        var path = [seed]
        for _ in 0..<maxSteps {
            guard let first = fieldDirection(at: point, poles: poles),
                  let mid = fieldDirection(at: point + first * (step / 2),
                                           poles: poles)
            else { break }
            point += mid * step
            path.append(point)
            if sinks.contains(where: { simd_distance(point, $0.at) < $0.radius }) {
                break
            }
            if simd_length(point) > escape { break }
        }
        return path
    }

    // MARK: Fields — two charges and the field between them

    private static func fields() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // Two big polished charges and seven fat field lines in the
        // reader's plane: the dipole as an emblem, not a survey.
        let separation: Float = 0.050
        let chargeRadius: Float = 0.026

        func charge(_ name: String, _ tint: UIColor, vertical: Bool) -> Entity {
            if let modeled = prop(name, longest: chargeRadius * 2 + 0.001) { return modeled }
            let orb = ball(chargeRadius, tint, glow: 0.6)
            let barMesh = Primitives.box(size: [0.022, 0.005, 0.005], cornerRadius: 0.0025)
            let across = ModelEntity(mesh: barMesh, materials: [Materials.unlit(.white)])
            across.position.z = chargeRadius - 0.001
            orb.addChild(across)
            if vertical {
                let up = ModelEntity(mesh: barMesh, materials: [Materials.unlit(.white)])
                up.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                up.position.z = chargeRadius - 0.001
                orb.addChild(up)
            }
            return orb
        }
        let positive = charge("ChargePlus", DesignTokens.Palette.positiveUI, vertical: true)
        let negative = charge("ChargeMinus", DesignTokens.Palette.negativeUI, vertical: false)
        positive.position.x = -separation
        negative.position.x = separation
        frame.addChild(positive)
        frame.addChild(negative)

        let plus = SIMD3<Float>(-separation, 0, 0)
        let minus = SIMD3<Float>(separation, 0, 0)
        let poles = [Pole(at: plus, strength: 1), Pole(at: minus, strength: -1)]

        // The axis line and three arcs each way, all leaving the + and
        // landing on the −; every one integrated through the real field.
        var paths: [[SIMD3<Float>]] = []
        var seeds: [SIMD3<Float>] = [[1, 0, 0]]
        for tilt in [Float(0.5), 1.05, 1.65] {
            for flip in [Float(1), -1] {
                seeds.append([cos(tilt), sin(tilt) * flip, 0])
            }
        }
        for out in seeds {
            let path = fieldLine(from: plus + out * (chargeRadius + 0.002),
                                 poles: poles, step: 0.0022, escape: 0.11,
                                 sinks: [(at: minus, radius: chargeRadius + 0.001)])
            if path.count > 3 { paths.append(path) }
        }
        if let flux = lines(paths, radius: 0.0034, DesignTokens.Palette.fieldLineUI) {
            frame.addChild(flux)
        }

        // Two arrowheads on every line, riding from + to −: a field line
        // without a direction is a contour.
        let headMesh = Primitives.cone(height: 0.012, radius: 0.005)
        let casingMesh = Primitives.cone(height: 0.0138, radius: 0.0064)
        let (casingMaterial, headMaterial) = Materials.contrastLine(
            DesignTokens.Palette.fieldLineUI)
        var riders: [(head: ModelEntity, path: [SIMD3<Float>], offset: Float)] = []
        for path in paths {
            for slot in 0..<2 {
                let head = ModelEntity(mesh: headMesh, materials: [headMaterial])
                let casing = ModelEntity(mesh: casingMesh, materials: [casingMaterial])
                casing.position.y = -0.0006
                head.addChild(casing)
                frame.addChild(head)
                riders.append((head, path, Float(slot) / 2))
            }
        }

        let cycle = 3.4
        return fit(root: root, frame: frame, cycle: cycle) { time in
            let travel = Float((time / cycle).truncatingRemainder(dividingBy: 1))
            for rider in riders {
                var t = travel + rider.offset
                t -= floor(t)
                let last = rider.path.count - 1
                let exact = t * Float(last)
                let index = min(Int(exact), last - 1)
                let blend = exact - Float(index)
                let here = rider.path[index]
                let next = rider.path[index + 1]
                rider.head.position = here + (next - here) * blend
                let tangent = next - here
                if simd_length(tangent) > 1e-6 {
                    rider.head.orientation = VectorFieldArrows
                        .rotationFromYAxis(to: simd_normalize(tangent))
                }
                // Faded at both ends of the run, so a head appears out of
                // the charge rather than being switched on in mid-air.
                let fade = min(1, min(t, 1 - t) * 7)
                rider.head.components.set(OpacityComponent(opacity: fade))
            }
        }
    }

    // MARK: Projectile — a launcher, an arc, a ball and a hoop

    /// A launch, integrated: quadratic drag, SI units; `fit` shrinks real
    /// metres into the frame.
    private static func launch(speed: Float, angle: Float, drag: Float,
                               floor: Float) -> [(time: Float, at: SIMD3<Float>)] {
        var path: [(Float, SIMD3<Float>)] = [(0, .zero)]
        var position = SIMD3<Float>.zero
        var velocity = SIMD3<Float>(cos(angle) * speed, sin(angle) * speed, 0)
        let gravity = SIMD3<Float>(0, -9.81, 0)
        let dt: Float = 0.002
        var time: Float = 0
        while time < 12 {
            let acceleration = gravity - drag * simd_length(velocity) * velocity
            velocity += acceleration * dt
            position += velocity * dt
            time += dt
            path.append((time, position))
            if position.y < floor { break }
        }
        return path.map { (time: $0.0, at: $0.1) }
    }

    private static func projectile() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // Fired steeply off a ledge so the emblem is not four times wider
        // than tall.
        let angle: Float = 62 * .pi / 180
        let floor: Float = -1.3
        let flown = launch(speed: 7, angle: angle, drag: 0.040, floor: floor)
        let duration = flown.last?.time ?? 1
        let reach = max(flown.last?.at.x ?? 1, 1e-3)

        /// Where the ball is at a fraction of its flight.
        func at(_ t: Float) -> SIMD3<Float> {
            let exact = min(max(t, 0), 1) * Float(flown.count - 1)
            let index = min(Int(exact), flown.count - 2)
            let blend = exact - Float(index)
            return flown[index].at + (flown[index + 1].at - flown[index].at) * blend
        }

        // One fat arc in the lab's orange.
        if let arc = line(flown.map(\.at), radius: reach * 0.018,
                          DesignTokens.Palette.projectileUI, opacity: 0.9) {
            frame.addChild(arc)
        }

        // The launcher: the room's own barrel on a machined puck, aimed
        // along the launch.
        let barrelLength = reach * 0.42
        let aim = Entity()
        aim.orientation = simd_quatf(angle: angle - .pi / 2, axis: [0, 0, 1])
        frame.addChild(aim)
        if let barrel = prop("LauncherBarrel", longest: barrelLength) {
            barrel.position.y = barrelLength / 2
            aim.addChild(barrel)
        } else {
            let barrel = rod(length: barrelLength, radius: barrelLength * 0.07,
                             DesignTokens.Palette.launcherUI, glow: 0.05)
            barrel.position.y = barrelLength / 2
            aim.addChild(barrel)
        }
        let puck = ModelEntity(
            mesh: Primitives.cylinder(height: reach * 0.06, radius: reach * 0.11),
            materials: [Materials.machined(UIColor(white: 0.55, alpha: 1), roughness: 0.4)])
        puck.position.y = -reach * 0.03
        frame.addChild(puck)

        // The hoop the shot drops through, lying where the arc lands. It sits
        // in a holder of its own so its landing pulse never fights `fit`.
        let landing = at(0.985)
        let hoopHolder = Entity()
        hoopHolder.position = landing
        frame.addChild(hoopHolder)
        if let hoop = ring(radius: reach * 0.13, tube: reach * 0.02,
                           UIColor(red: 0.35, green: 0.95, blue: 0.6, alpha: 1)) {
            hoopHolder.addChild(hoop)
        }

        let ballEntity = ball(reach * 0.09, DesignTokens.Palette.projectileUI, glow: 0.55)
        frame.addChild(ballEntity)

        // The ball fades in leaving the barrel and out into the hoop, where it
        // used to blink on and off; the hoop answers the landing with a short
        // swell.
        let period = Double(duration) + 0.6
        let fade: Float = 0.08
        return fit(root: root, frame: frame, cycle: period) { time in
            let t = Float((time.truncatingRemainder(dividingBy: period)) / Double(duration))
            ballEntity.position = at(min(t, 1))
            let visible = t <= 1 ? min(1, t / fade, (1 - t) / fade) : 0
            ballEntity.components.set(OpacityComponent(opacity: max(visible, 0)))
            let since = (t - 1) * duration
            let pulse = since > 0 && since < 0.45 ? sin(.pi * since / 0.45) : 0
            hoopHolder.scale = SIMD3(repeating: 1 + 0.14 * pulse)
        }
    }

    // MARK: Gravity — a star and one world

    private static func gravity() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // Tilted toward the reader: flat, an orbit projects to a streak.
        let system = Entity()
        system.orientation = simd_quatf(angle: 34 * .pi / 180, axis: [1, 0, 0])
        frame.addChild(system)

        CelestialTextures.warmUp()
        let sun = world("Sun", radius: 0.026)
        system.addChild(sun)
        let corona = ModelEntity(
            mesh: Primitives.sphere(radius: 0.040),
            materials: [Materials.unlit(DesignTokens.Palette.celestialUI("Sun"), opacity: 0.22)])
        system.addChild(corona)

        /// True anomaly from mean anomaly, by Newton on Kepler's equation.
        func trueAnomaly(meanAnomaly: Double, eccentricity: Double) -> Double {
            var E = meanAnomaly
            for _ in 0..<8 {
                let f = E - eccentricity * sin(E) - meanAnomaly
                E -= f / (1 - eccentricity * cos(E))
            }
            return 2 * atan(sqrt((1 + eccentricity) / (1 - eccentricity)) * tan(E / 2))
        }

        // One world on one honest ellipse, the star at a focus.
        let semiMajor: Double = 0.064, eccentricity: Double = 0.18
        let a = Float(semiMajor), e = Float(eccentricity)
        let semiLatus = a * (1 - e * e)
        let path = (0...96).map { step -> SIMD3<Float> in
            let nu = Float(step) / 96 * 2 * .pi
            let r = semiLatus / (1 + e * cos(nu))
            return SIMD3(r * cos(nu), 0, r * sin(nu))
        }
        if let track = line(path, radius: 0.0028, .white, opacity: 0.6) {
            system.addChild(track)
        }
        let planet = world("Earth", radius: 0.014)
        let tilt = simd_quatf(angle: 0.35, axis: simd_normalize(SIMD3(0.3, 1, 0.2)))
        planet.orientation = tilt
        system.addChild(planet)

        var worlds: [(entity: ModelEntity, name: String)] = [(sun, "Sun"), (planet, "Earth")]
        var appliedTextureVersion = CelestialTextures.version
        let period = 6.0
        return fit(root: root, frame: frame, cycle: period, centredOn: .zero) { time in
            if appliedTextureVersion != CelestialTextures.version {
                appliedTextureVersion = CelestialTextures.version
                for body in worlds {
                    body.entity.model?.materials = [celestialMaterial(body.name)]
                }
            }
            let mean = 2 * Double.pi * (time / period).truncatingRemainder(dividingBy: 1)
            let nu = Float(trueAnomaly(meanAnomaly: mean, eccentricity: eccentricity))
            let r = semiLatus / (1 + e * cos(nu))
            planet.position = SIMD3(r * cos(nu), 0, r * sin(nu))
            planet.orientation = tilt * simd_quatf(angle: Float(time) * 0.8, axis: [0, 1, 0])
            corona.scale = SIMD3(repeating: 1 + 0.05 * Float(sin(time * 1.3)))
        }
    }

    // MARK: Circuits — a loop, a battery and a bulb

    private static func circuits() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // A rounded rectangular loop of fat copper wire.
        let width: Float = 0.058, height: Float = 0.050
        func onLoop(_ t: Float) -> SIMD3<Float> {
            let angle = t * 2 * .pi
            let cx = cos(angle), sy = sin(angle)
            return SIMD3(width * sign(cx) * pow(abs(cx), 0.55),
                         height * sign(sy) * pow(abs(sy), 0.55), 0)
        }
        if let wire = line((0...64).map { onLoop(Float($0) / 64) },
                           radius: 0.0036, DesignTokens.Palette.copperUI) {
            frame.addChild(wire)
        }

        // The battery and the bulb the workshop itself uses, big.
        let battery = prop("CircuitBattery", longest: 0.046) ?? ModelEntity(
            mesh: Primitives.box(size: [0.040, 0.018, 0.018], cornerRadius: 0.005),
            materials: [Materials.energized(
                UIColor(red: 0.24, green: 0.42, blue: 0.28, alpha: 1), metallic: 0.7, glow: 0)])
        battery.position = [0, -height, 0]
        frame.addChild(battery)

        let bulbHolder = Entity()
        bulbHolder.position = [0, height, 0]
        frame.addChild(bulbHolder)
        if let bulb = prop("CircuitBulb", longest: 0.036) {
            bulbHolder.addChild(bulb)
        } else {
            bulbHolder.addChild(
                ball(0.017, UIColor(red: 1.0, green: 0.87, blue: 0.45, alpha: 1), glow: 1))
        }
        let halo = ModelEntity(
            mesh: Primitives.sphere(radius: 0.026),
            materials: [Materials.unlit(UIColor(red: 1, green: 0.88, blue: 0.5, alpha: 1),
                                        opacity: 0.25)])
        bulbHolder.addChild(halo)

        // Charge carriers, big enough to count, going round.
        var carriers: [ModelEntity] = []
        for _ in 0..<8 {
            let dot = ModelEntity(
                mesh: Primitives.sphere(radius: 0.0042),
                materials: [Materials.energized(DesignTokens.Palette.electronUI, glow: 0.9)])
            frame.addChild(dot)
            carriers.append(dot)
        }

        let lapTime = 2.4
        return fit(root: root, frame: frame, cycle: lapTime) { time in
            let progress = Float((time / lapTime).truncatingRemainder(dividingBy: 1))
            for (index, carrier) in carriers.enumerated() {
                let t = (progress + Float(index) / Float(carriers.count))
                    .truncatingRemainder(dividingBy: 1)
                carrier.position = onLoop(t)
            }
            // The filament breathes, a lit thing rather than a painted one.
            let glow = 0.8 + 0.2 * Float(sin(time * 2.1))
            halo.scale = SIMD3(repeating: 0.9 + glow * 0.25)
            halo.components.set(OpacityComponent(opacity: glow * 0.5))
        }
    }

    // MARK: Magnetism — one bar magnet and its field

    private static func magnetism() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // The magnet and its field rock together, side-on to the reader: the
        // field belongs to the magnet, and the classic picture stays legible
        // through the whole swing.
        let turntable = Entity()
        frame.addChild(turntable)

        let barLength: Float = 0.100
        let halfLength = barLength / 2
        if let modeled = prop("BarMagnet", longest: barLength) {
            turntable.addChild(modeled)
        } else {
            let half = Primitives.box(size: [halfLength, 0.022, 0.022], cornerRadius: 0.003)
            let south = ModelEntity(mesh: half, materials: [
                Materials.energized(UIColor(red: 0.25, green: 0.47, blue: 0.95, alpha: 1), glow: 0.25)])
            south.position.x = -halfLength / 2
            let north = ModelEntity(mesh: half, materials: [
                Materials.energized(UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1), glow: 0.25)])
            north.position.x = halfLength / 2
            turntable.addChild(south)
            turntable.addChild(north)
        }

        // Eight fat loops out of the north face and round to the south, in
        // two planes, integrated through the two-pole field and kept close
        // to the bar so the magnet stays the biggest thing in the picture.
        let poles = [Pole(at: [-halfLength, 0, 0], strength: -1),
                     Pole(at: [halfLength, 0, 0], strength: 1)]
        var paths: [[SIMD3<Float>]] = []
        // Seeded near the pole's side, not its face: a line leaving close to
        // the axis runs to the horizon, one leaving sideways wraps the bar.
        for roll in [Float(0), .pi / 2] {
            for tilt in [Float(1.15), 1.5] {
                for flip in [Float(1), -1] {
                    let out = SIMD3<Float>(cos(tilt), sin(tilt) * cos(roll) * flip,
                                           sin(tilt) * sin(roll) * flip)
                    let path = fieldLine(from: poles[1].at + out * 0.014, poles: poles,
                                         step: 0.0025, escape: 0.20,
                                         sinks: [(at: poles[0].at, radius: 0.014)],
                                         maxSteps: 1200)
                    if path.count > 3 { paths.append(path) }
                }
            }
        }
        if let field = lines(paths, radius: 0.0032, MagnetismRenderer.lineColor) {
            turntable.addChild(field)
        }

        let period = 7.0
        return fit(root: root, frame: frame, cycle: period) { time in
            let rock = 0.45 * Float(sin(2 * .pi * time / period))
            turntable.orientation = simd_quatf(angle: rock, axis: [0, 1, 0])
        }
    }

    // MARK: Light — white light through a prism, fanned into a spectrum

    private static func optics() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // The lab's own prism, face-on, and its light traced live by the lab's
        // own tracer: a white beam in, a spectrum out. It rocks through its
        // least deviation, so the fan visibly swings out and turns back.
        let holder = Entity()
        holder.addChild(ModelEntity(mesh: OpticsMeshes.prism,
                                    materials: [Materials.opticalGlass(opacity: 0.4)]))
        frame.addChild(holder)
        let unit = Primitives.cylinder(height: 1, radius: 1)
        // Born parked: a unit cylinder is a metre across, and an unused one left
        // at full size would set the emblem's measured bounds.
        let beams = (0..<20).map { _ -> ModelEntity in
            let beam = ModelEntity(mesh: unit, materials: [])
            beam.scale = SIMD3(repeating: 1e-5)
            beam.isEnabled = false
            return beam
        }
        for beam in beams { frame.addChild(beam) }

        let glass = Glass.sf11
        let apex = OpticsModel.prismApex
        let delta = LightTracer.minimumDeviation(apexAngle: apex, index: glass.index(nanometers: 550))
        let incoming = SIMD3<Double>(cos(delta / 2), sin(delta / 2), 0)
        let corners = OpticalElement.prismCorners(apexAngle: apex, side: OpticsModel.prismSide)
        let face = (corners[0] + corners[1]) / 2
        let start = SIMD3(face.x, face.y, 0) - 0.12 * incoming
        let colours: [Double] = [410, 450, 490, 530, 570, 610, 650]
        let period = 9.0

        return fit(root: root, frame: frame, cycle: period) { time in
            let rock = 0.10 * sin(2 * .pi * time / period)
            let turn = simd_quatd(angle: rock, axis: SIMD3(0, 0, 1))
            holder.orientation = simd_quatf(ix: Float(turn.imag.x), iy: Float(turn.imag.y),
                                            iz: Float(turn.imag.z), r: Float(turn.real))
            let prism = OpticalElement(position: .zero, orientation: turn,
                                       shape: .prism(apexAngle: apex, side: OpticsModel.prismSide,
                                                     length: OpticsModel.prismHeight),
                                       glass: glass)
            let trace = LightTracer.trace(
                colours.map { LightTracer.Ray(origin: start, direction: incoming,
                                              nanometers: $0, power: 1 / 7) },
                elements: [prism], room: LightTracer.Room(maxSegment: 0.13),
                options: .init(followsPartialReflections: false))
            let strokes = OpticsBeamLayout.strokes(trace)
            for (index, beam) in beams.enumerated() {
                guard index < strokes.count else {
                    beam.isEnabled = false
                    beam.scale = SIMD3(repeating: 1e-5)
                    continue
                }
                let stroke = strokes[index]
                let length = simd_distance(stroke.a, stroke.b)
                beam.isEnabled = length > 1e-5
                beam.position = (stroke.a + stroke.b) / 2
                beam.orientation = rotation(from: [0, 1, 0], to: (stroke.b - stroke.a) / max(length, 1e-5))
                beam.scale = [0.0026, length, 0.0026]
                let rgb = stroke.color
                func encode(_ v: Double) -> CGFloat {
                    CGFloat(v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055)
                }
                beam.model?.materials = [Materials.unlit(UIColor(
                    red: encode(rgb.x), green: encode(rgb.y), blue: encode(rgb.z), alpha: 1))]
            }
        }
    }

    // MARK: Pendulums — one pendulum, swinging

    private static func pendulums() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // A beam, a cable and one big turned-brass bob.
        let pivotY: Float = 0.052
        let beam = ModelEntity(
            mesh: Primitives.box(size: [0.11, 0.009, 0.014], cornerRadius: 0.004),
            materials: [Materials.machined(UIColor(white: 0.62, alpha: 1), roughness: 0.35)])
        beam.position.y = pivotY
        frame.addChild(beam)

        let length: Float = 0.078
        let pivot = Entity()
        pivot.position = [0, pivotY, 0]
        frame.addChild(pivot)
        if let cable = line([[0, 0, 0], [0, -length, 0]], radius: 0.0022,
                            UIColor(white: 0.70, alpha: 1)) {
            pivot.addChild(cable)
        }
        let bobSpan: Float = 0.046
        if let bob = prop("PendulumBob", longest: bobSpan) {
            bob.position.y = -length - 0.02265 * (bobSpan / 0.0537)
            pivot.addChild(bob)
        } else {
            let bob = ball(0.018, DesignTokens.Palette.pendulumsAccentUI, glow: 0.15)
            bob.position.y = -length
            pivot.addChild(bob)
        }

        // A spherical swing: a wide ellipse that slowly precesses, which is
        // what the lab promises a bob thrown off axis will do.
        let period = Double(length.squareRoot()) * 6.2
        let cycle = 24.0
        return fit(root: root, frame: frame, cycle: cycle) { time in
            let sweep = 2 * .pi * time / period
            let precession = Float(time) * 0.12
            let a: Float = 0.55, b: Float = 0.16
            var offset = SIMD3<Float>(a * Float(sin(sweep)), 0, b * Float(cos(sweep)))
            offset = SIMD3(offset.x * cos(precession) - offset.z * sin(precession), 0,
                           offset.x * sin(precession) + offset.z * cos(precession))
            let drop = sqrt(max(1 - simd_length_squared(offset), 0.05))
            let direction = simd_normalize(SIMD3(offset.x, -drop, offset.z))
            pivot.orientation = rotation(from: [0, -1, 0], to: direction)
        }
    }

    // MARK: Fallback — a new module gets something until it has art

    private static func fallback() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)
        let sphere = ball(0.030, UIColor(white: 0.7, alpha: 1), glow: 0.3)
        frame.addChild(sphere)
        return fit(root: root, frame: frame, cycle: 4.5) { time in
            sphere.scale = SIMD3(repeating: 1 + 0.06 * Float(sin(time * 1.4)))
        }
    }
}

/// `sign` for Float without importing anything heavier.
private func sign(_ value: Float) -> Float {
    value < 0 ? -1 : 1
}
