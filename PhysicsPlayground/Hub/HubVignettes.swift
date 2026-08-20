//
//  HubVignettes.swift
//  Physics Playground — Hub
//
//  The hub miniatures, each returning its animation closure alongside the
//  geometry it drives, so a model and its motion cannot drift apart. Solid
//  apparatus loads from usdz (some the same asset the room loads); things
//  that must flex — field lines, trajectories, orbits, cables — stay
//  procedural. Three rules:
//    1. A vignette NEVER writes its own root transform; content hangs off
//       an inner `frame`.
//    2. `fit` owns `frame.position`/`frame.scale`; an animation needing
//       its own scale gets a third level beneath the frame.
//    3. Every drawn line goes through `lines(_:)` (dark casing, bright core).
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
        /// What the miniature's own geometry fills, swept across its
        /// whole cycle. The square around it is guaranteed by `fit`;
        /// this is the number that says whether what sits inside the
        /// square is a picture or a streak.
        let contentExtents: SIMD3<Float>
        /// Called when the host has an unfold fraction to report, 0…1.
        /// Only the labs emblem uses it; every gallery exhibit leaves it
        /// nil, because a terrace has nothing to be open or shut about.
        let setOpenness: ((Float) -> Void)?

        init(entity: Entity,
             animate: @escaping (Double) -> Void,
             contentExtents: SIMD3<Float> = .zero,
             setOpenness: ((Float) -> Void)? = nil) {
            self.entity = entity
            self.animate = animate
            self.contentExtents = contentExtents
            self.setOpenness = setOpenness
        }
    }

    /// The half-extent of the square every miniature is normalised into.
    ///
    /// Both hosts fit `max(extents.x, extents.y)` to their own slot
    /// (`HubSpaceView.buildExhibit`, `Palette.init`), so a miniature that
    /// is wide and short is scaled by its width and comes out as a streak
    /// beside a square one. Normalising to a common square here makes
    /// that division a change of units and nothing else — which is the
    /// only way six differently-shaped exhibits can read as one set.
    static let frameHalf: Float = 0.085

    static func make(for moduleID: String) -> Built {
        switch moduleID {
        case "electrostatics": fields()
        case "circuits": circuits()
        case "magnetism": magnetism()
        case "kinematics": projectile()
        case "pendulums": pendulums()
        case "gravitylab": gravity()
        case "labs": gyroscope()
        default: fallback()
        }
    }

    // MARK: The common frame

    /// Centres `frame` on the root's origin and normalises it to the common
    /// square, sampling a WHOLE cycle of the motion (not the resting pose,
    /// which is smaller and would overflow the bubble mid-swing).
    /// `centredOn` overrides which point lands in the middle — a solar
    /// system centres on its star's focus, not the ellipses' box centre.
    private static func fit(root: Entity, frame: Entity,
                            cycle: Double,
                            centredOn pivot: SIMD3<Float>? = nil,
                            animate: @escaping (Double) -> Void,
                            setOpenness: ((Float) -> Void)? = nil) -> Built {
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
        // The offset is the SCALED centre negated (the frame scale applies
        // to the centre just measured).
        frame.scale = SIMD3(repeating: scale)
        frame.position = -centre * scale

        // An invisible square proxy on the ROOT so both hosts measure ONE
        // pose-independent box (they measure at rest, which is smaller than
        // mid-swing, and would otherwise hand each miniature a different
        // number to divide by).
        let proxy = ModelEntity(
            mesh: .generateBox(size: [frameHalf * 2, frameHalf * 2, 0.0005]),
            materials: [{
                var clear = UnlitMaterial(color: .white)
                clear.blending = .transparent(opacity: .init(floatLiteral: 0))
                return clear
            }()])
        proxy.name = "vignette-square"
        proxy.components.set(OpacityComponent(opacity: 0))
        root.addChild(proxy)

        animate(0)
        return Built(entity: root, animate: animate,
                     contentExtents: reach * 2 * scale,
                     setOpenness: setOpenness)
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

    /// A bundle of drawn lines in the two design-system passes (near-black
    /// casing under a bright core, so they don't dissolve against a bright
    /// wall). All paths share ONE mesh per pass — `TubeMesh` takes a list
    /// of polylines — so a sixteen-line bundle is two draw calls.
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

    /// A prop, centred on its own origin and scaled so its longest
    /// dimension is `longest`. Prototypes come from the shared
    /// `PropCache` (warmed off-main before the space opens); every call
    /// site below keeps the geometry it used to draw as its fallback,
    /// so a miniature degrades instead of vanishing.
    ///
    /// Measured rather than assumed: these assets were authored at real
    /// bench sizes, and a miniature has no business knowing which of them
    /// happens to be 30 cm long.
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

    /// A celestial body wearing the same procedural texture Gravity Lab
    /// gives it, falling back to its accent colour until the texture has
    /// been drawn.
    ///
    /// `CelestialTextures` renders off the main path and publishes a
    /// `version` as each one lands, so the first frames of a freshly
    /// launched hub genuinely have no texture to apply — which is why
    /// this is a re-appliable material and not a one-shot.
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
        ModelEntity(mesh: .generateSphere(radius: radius),
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

    /// One field line, integrated through a set of point sources.
    ///
    /// Field lines are the one thing in these miniatures with an exact
    /// answer, and both electromagnetic exhibits used to draw decoration
    /// instead: a cosine arc for the dipole, and closed circles threading
    /// the gap for the magnets — which is not what a two-bar field looks
    /// like anywhere. Marching `dr/ds = Ê` by midpoint costs a few
    /// thousand multiplies once, at build time, and gets the topology
    /// right. Including the lines that never close, which is what stops
    /// the dipole reading as a decorative ellipse.
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

    // MARK: Fields — a dipole, and the flux crossing it

    private static func fields() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // The charges hold still. The old miniature eased them apart and
        // back while counter-scaling the frame by exactly the same
        // factor, so the pair never appeared to move at all — the whole
        // visible effect was the field lines growing and shrinking, which
        // is the one thing a static charge pair does not do.
        //
        // What a field does instead is have a DIRECTION, so that is what
        // moves here: arrowheads riding the lines from + to −.
        let separation: Float = 0.042
        let chargeRadius: Float = 0.019

        // The charges as PHYSICAL conductors — polished metal spheres in
        // the palette's own red and blue, the sign moulded proud of the
        // surface on the reader's side (`Tools/moduleprops.py`). The
        // glowing ball with white bars floating beside it survives only
        // as the fallback: a sign that is part of the object catches the
        // key light the way UI stuck next to it never did.
        func charge(_ name: String, _ tint: UIColor, vertical: Bool) -> Entity {
            // Authored: a 0.038 sphere whose sign stands 0.0009 proud,
            // so the longest span is 0.0389 — normalising to 0.039
            // reproduces the 0.019 radius the layout was composed for.
            if let modeled = prop(name, longest: 0.039) { return modeled }
            let orb = ball(chargeRadius, tint, glow: 0.6)
            let barMesh = MeshResource.generateBox(size: [0.016, 0.0038, 0.0038],
                                                   cornerRadius: 0.0019)
            let signMaterial = UnlitMaterial(color: .white)
            let across = ModelEntity(mesh: barMesh, materials: [signMaterial])
            across.position.z = chargeRadius - 0.001
            orb.addChild(across)
            if vertical {
                let up = ModelEntity(mesh: barMesh, materials: [signMaterial])
                up.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                up.position.z = chargeRadius - 0.001
                orb.addChild(up)
            }
            return orb
        }
        let positive = charge("ChargePlus", DesignTokens.Palette.positiveUI,
                              vertical: true)
        let negative = charge("ChargeMinus", DesignTokens.Palette.negativeUI,
                              vertical: false)
        positive.position.x = -separation
        negative.position.x = separation
        frame.addChild(positive)
        frame.addChild(negative)

        let plus = SIMD3<Float>(-separation, 0, 0)
        let minus = SIMD3<Float>(separation, 0, 0)
        let poles = [Pole(at: plus, strength: 1),
                     Pole(at: minus, strength: -1)]
        // Tracing BACKWARD means following the field of the negated
        // charges — same integrator, opposite arrows.
        let reversedPoles = poles.map { Pole(at: $0.at, strength: -$0.strength) }

        // Seeded by FLUX: uniform angles around BOTH charges, in two
        // perpendicular planes. Out of the + along the field; into the −
        // AGAINST the field, keeping only the lines that escape — a
        // backward trace that lands on the + is a line the forward pass
        // already drew. Seeding one charge alone left the other visibly
        // barer: every line out of the + that escaped to infinity has an
        // incoming mirror at the −, and nothing was drawing those. (The
        // old hand-picked tilts also skipped two flip lines outright,
        // which is where the lopsidedness came from.) Equal charges,
        // equal flux, equal lines — drawn once each.
        var paths: [[SIMD3<Float>]] = []
        let tiltCount = 4
        for roll in [Float(0), .pi / 2] {
            for index in 0..<tiltCount {
                let tilt = (Float(index) + 0.5) * .pi / Float(tiltCount)
                for flip in [Float(1), -1] {
                    let out = SIMD3<Float>(cos(tilt),
                                           sin(tilt) * cos(roll) * flip,
                                           sin(tilt) * sin(roll) * flip)
                    let outgoing = fieldLine(
                        from: plus + out * (chargeRadius + 0.0015),
                        poles: poles, step: 0.0022, escape: 0.088,
                        sinks: [(at: minus, radius: chargeRadius + 0.001)])
                    if outgoing.count > 3 { paths.append(outgoing) }

                    // The mirrored seed on the −, so its incoming fan
                    // sits at the same angles as the +'s outgoing one.
                    let incoming = fieldLine(
                        from: minus + SIMD3(-out.x, out.y, out.z)
                            * (chargeRadius + 0.0015),
                        poles: reversedPoles, step: 0.0022, escape: 0.088,
                        sinks: [(at: plus, radius: chargeRadius + 0.001)])
                    if incoming.count > 3, let far = incoming.last,
                       simd_distance(far, plus) > chargeRadius + 0.004 {
                        // Escaped rather than landed on the + — kept,
                        // and REVERSED so the stored order runs along
                        // the field, the direction the arrowheads ride.
                        paths.append(incoming.reversed())
                    }
                }
            }
        }
        let flux = lines(paths, radius: 0.0016,
                         DesignTokens.Palette.fieldLineUI, opacity: 0.92)
        flux.map { frame.addChild($0) }

        // Arrowheads: three per line on a handful of the lines, walking
        // from + to −. A field line without a direction is a contour; the
        // whole reason this module exists is that the field points
        // somewhere.
        let headMesh = MeshResource.generateCone(height: 0.0072, radius: 0.0030)
        // The casing cone rides just behind its core, slightly fatter —
        // the same two-pass darkness every line got, because a bare
        // bright cone washes out on a lit wall exactly the way the
        // lines used to.
        let casingMesh = MeshResource.generateCone(height: 0.0086, radius: 0.0040)
        let (casingMaterial, headMaterial) = Materials.contrastLine(
            DesignTokens.Palette.fieldLineUI)
        var riders: [(head: ModelEntity, path: [SIMD3<Float>], offset: Float)] = []
        for (index, path) in paths.enumerated() where index % 2 == 0 {
            for slot in 0..<2 {
                let head = ModelEntity(mesh: headMesh, materials: [headMaterial])
                let casing = ModelEntity(mesh: casingMesh, materials: [casingMaterial])
                casing.position.y = -0.0004
                head.addChild(casing)
                frame.addChild(head)
                riders.append((head, path, Float(slot) / 2))
            }
        }

        return fit(root: root, frame: frame, cycle: 3.4) { time in
            for rider in riders {
                let travel = Float((time / 3.4).truncatingRemainder(dividingBy: 1))
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

    // MARK: Projectile — a real trajectory, and the one drag took away

    /// A launch, integrated. Quadratic drag, SI units, and the same
    /// launch again with the air removed.
    ///
    /// The ghost is the point. The module promises to "bend their arcs
    /// with gravity AND drag", and one arc cannot say that — two can,
    /// because the gap between them IS the drag. The numbers are real
    /// metres and seconds; `fit` shrinks the result into the bubble
    /// afterwards, so nothing here has to be authored in miniature.
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

        // Fired off a ledge and steeply, which is a composition decision
        // as much as a physical one: a 42° shot lands where it started
        // and the whole exhibit came out four times wider than it was
        // tall — a streak on a terrace of otherwise square neighbours.
        // Climbing the angle and letting the ball finish below the muzzle
        // buys the vertical extent honestly, without bending the arc.
        let angle: Float = 62 * .pi / 180
        let floor: Float = -1.3
        let flown = launch(speed: 7, angle: angle, drag: 0.040, floor: floor)
        let ghost = launch(speed: 7, angle: angle, drag: 0, floor: floor)
        let duration = flown.last?.time ?? 1

        // EVERYTHING below is in metres of real trajectory, and the
        // trajectory is about five of them across. A tube authored at
        // the 1.6 mm the other miniatures use would come out at seven
        // hundredths of a millimetre once `fit` had shrunk the scene into
        // its square — which is exactly what happened, and why the first
        // render of this exhibit was a row of dots with no arc under
        // them. Sizes here are written as a fraction of the flight.
        let reach = max(ghost.last?.at.x ?? 1, 1e-3)

        /// Where the real ball is at a fraction of its flight.
        func at(_ t: Float) -> SIMD3<Float> {
            let exact = min(max(t, 0), 1) * Float(flown.count - 1)
            let index = min(Int(exact), flown.count - 2)
            let blend = exact - Float(index)
            return flown[index].at + (flown[index + 1].at - flown[index].at) * blend
        }

        // The drag-free arc first, so the real one is drawn over it. It
        // is the quieter of the two but it is not a whisper: at 0.3
        // opacity it vanished, and an invisible ghost is a third of the
        // composition taken up by nothing — which also drags the centre
        // of the exhibit sideways, because `fit` can see it even when
        // nobody else can.
        if let ideal = line(ghost.map(\.at), radius: reach * 0.0062,
                            UIColor(white: 0.86, alpha: 1), opacity: 0.55) {
            frame.addChild(ideal)
        }
        if let arc = line(flown.map(\.at), radius: reach * 0.0085,
                          DesignTokens.Palette.projectileUI, opacity: 0.8) {
            frame.addChild(arc)
        }

        // The launcher, aimed along the launch — the same barrel the room
        // uses, so the miniature and the bench are the same object.
        let barrelLength = reach * 0.40
        let aim = Entity()
        aim.orientation = simd_quatf(angle: angle - .pi / 2, axis: [0, 0, 1])
        frame.addChild(aim)
        if let barrel = prop("LauncherBarrel", longest: barrelLength) {
            // The asset is authored along +Y; sliding it up half its own
            // length puts the breech on the origin and the muzzle on the
            // start of the arc.
            barrel.position.y = barrelLength / 2
            aim.addChild(barrel)
        } else {
            let barrel = rod(length: barrelLength, radius: barrelLength * 0.055,
                             DesignTokens.Palette.launcherUI, glow: 0.05)
            barrel.position.y = barrelLength / 2
            aim.addChild(barrel)
        }
        // The carriage the barrel sits in, with its elevation quadrant
        // (`Tools/moduleprops.py`). Authored numbers, mapped through one
        // scale: the box spans z 0...0.1082 (the quadrant rim is the top
        // of the part), the trunnion is at z 0.068, and the tick face is
        // at y -0.0246. The importer centres the box, so the trunnion is
        // placed by its offset from that centre.
        let carriageScale = reach * 0.16 / 0.104
        if let carriage = prop("LauncherCarriage",
                               longest: 0.1082 * carriageScale) {
            carriage.position.y = -(0.068 - 0.1082 / 2) * carriageScale
            frame.addChild(carriage)

            // The pointer rides the launch angle, so whatever angle this
            // miniature actually fires at is the angle the instrument
            // reads — a baked pointer would lie the day the angle
            // changed. Its authored ORIGIN is its hinge, so the import
            // centring is undone rather than trusted: zeroing the inner
            // model puts the authored origin back on the holder's.
            if let pointer = prop("QuadrantPointer",
                                  longest: 0.0503 * carriageScale) {
                pointer.children.first?.position = .zero
                pointer.position.z = 0.0252 * carriageScale
                pointer.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
                frame.addChild(pointer)
            }
        } else {
            let base = ModelEntity(
                mesh: .generateCylinder(height: reach * 0.062,
                                        radius: reach * 0.085),
                materials: [Materials.machined(UIColor(white: 0.55, alpha: 1),
                                               roughness: 0.4)])
            base.position.y = -reach * 0.031
            frame.addChild(base)
        }

        // The target, where the real arc actually lands — a ring on a
        // mast standing on the floor the ball falls to, with the ring's
        // centre ON the trajectory: the placement walks the flown arc
        // back to the ring's own height, so the shot threads the ring as
        // a consequence of the physics rather than a decision. (The
        // drag-free ghost misses it, which is the drag made visible.)
        let landing = flown.last?.at ?? .zero
        let standScale = reach * 0.095 / 0.0265   // ring inner radius
        if let target = prop("TargetStand", longest: 0.0782 * standScale) {
            // Base bottom sits 0.060 below the ring plane (authored), so
            // a base on the floor puts the ring at this height:
            let ringHeight = floor + 0.060 * standScale
            var through = landing
            for sample in stride(from: 1.0, through: 0.0, by: -0.01) {
                let point = at(Float(sample))
                if point.y >= ringHeight { through = point; break }
            }
            // Authored ring centre (-0.029, 0, 0.060) against a box
            // centred at (-0.0202, 0, 0.0311).
            target.position = [through.x + 0.00885 * standScale,
                               through.y - 0.02895 * standScale, 0]
            frame.addChild(target)
        } else if let hoop = ring(radius: reach * 0.095, tube: reach * 0.012,
                                  UIColor(red: 0.35, green: 0.95, blue: 0.6, alpha: 1)) {
            hoop.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            hoop.position = landing + SIMD3(0, reach * 0.095, 0)
            frame.addChild(hoop)
        }

        // Strobe dots: equal steps in TIME, so their spacing tells the
        // story — stretched on the way up, bunched at the apex.
        var dots: [ModelEntity] = []
        let dotCount = 9
        for _ in 0..<dotCount {
            let dot = ModelEntity(
                mesh: .generateSphere(radius: reach * 0.030),
                materials: [Materials.energized(
                    DesignTokens.Palette.projectileUI, glow: 0.7)])
            frame.addChild(dot)
            dots.append(dot)
        }
        let ballEntity = ball(reach * 0.062,
                              DesignTokens.Palette.projectileUI, glow: 0.55)
        frame.addChild(ballEntity)

        let period = Double(duration) + 0.7
        return fit(root: root, frame: frame, cycle: period) { time in
            let t = Float((time.truncatingRemainder(dividingBy: period))
                          / Double(duration))
            ballEntity.position = at(min(t, 1))
            ballEntity.components.set(OpacityComponent(opacity: t <= 1 ? 1 : 0))
            // The trail fills in behind the ball and clears on each throw.
            for (index, dot) in dots.enumerated() {
                let sample = Float(index + 1) / Float(dotCount + 1)
                dot.position = at(sample)
                let shown = sample < t
                dot.components.set(OpacityComponent(
                    opacity: shown ? 0.3 + 0.5 * max(0, 1 - (t - sample)) : 0))
            }
        }
    }

    // MARK: Gravity — a tilted system, and one orbit obeying Kepler

    private static func gravity() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // Tilted TOWARD the reader, and the sign is the whole point.
        //
        // Flat on the XZ plane the orbits projected to two horizontal
        // streaks. The first fix tilted −40°, which leans the plane's far
        // edge UP and its normal away from a viewer who is already
        // looking down on a waist-high exhibit — the two rotations
        // cancelled and the ellipses came out flatter than before.
        // Leaning +28° into the eyeline opens them to about two-thirds of
        // round: unmistakably ellipses, still unmistakably in 3-D.
        let system = Entity()
        system.orientation = simd_quatf(angle: 28 * .pi / 180, axis: [1, 0, 0])
        frame.addChild(system)

        // The same worlds Gravity Lab itself puts in the room: a
        // granulated Sun, a blotchy blue Earth with polar caps, a Mars
        // with dark maria. `CelestialTextures` draws them once and hands
        // them to whoever asks, so the miniature and the lab are wearing
        // the same skins rather than two flat accent colours that merely
        // agree about hue.
        CelestialTextures.warmUp()

        let sun = world("Sun", radius: 0.018)
        system.addChild(sun)
        var coronaMaterial = UnlitMaterial(color: DesignTokens.Palette.celestialUI("Sun"))
        coronaMaterial.blending = .transparent(opacity: 0.22)
        let corona = ModelEntity(mesh: .generateSphere(radius: 0.029),
                                 materials: [coronaMaterial])
        system.addChild(corona)

        /// True anomaly from mean anomaly, by Newton on Kepler's
        /// equation. Eight iterations is convergence to well under a
        /// pixel even at the comet's e = 0.62 — five was enough for the
        /// planets, but Newton slows near periapsis as e climbs — and it
        /// is the whole reason the outer bodies visibly race at
        /// periapsis and crawl at apoapsis instead of sliding round at a
        /// constant rate.
        func trueAnomaly(meanAnomaly: Double, eccentricity: Double) -> Double {
            var E = meanAnomaly
            for _ in 0..<8 {
                let f = E - eccentricity * sin(E) - meanAnomaly
                E -= f / (1 - eccentricity * cos(E))
            }
            let half = sqrt((1 + eccentricity) / (1 - eccentricity))
                * tan(E / 2)
            return 2 * atan(half)
        }

        struct Orbit {
            let planet: Entity
            let tilt: simd_quatf
            let semiMajor: Double
            let eccentricity: Double
            let period: Double
        }
        var orbits: [Orbit] = []
        /// Every textured body, so the closure can re-skin them when a
        /// texture finishes drawing. Keyed by the name they were built
        /// under, because that is what `CelestialTextures` answers to.
        var worlds: [(entity: ModelEntity, name: String)] = [(sun, "Sun")]
        var appliedTextureVersion = CelestialTextures.version

        // Two worlds; periods obey Kepler's third law (outer slower by
        // (a₂/a₁)^³ᐟ²). `argument` (argument of periapsis, a real element
        // the lab computes) also turns the outer orbit across the frame so
        // its eccentric overhang spreads over both axes.
        let plan: [(semiMajor: Double, eccentricity: Double, argument: Float,
                    name: String, size: Float)] = [
            (0.042, 0.10, 0, "Earth", 0.0096),
            (0.072, 0.30, 2.2, "Mars", 0.0078),
        ]
        let baseSemiMajor = plan[0].semiMajor
        let basePeriod = 5.2

        for spec in plan {
            let pivot = Entity()
            pivot.orientation = simd_quatf(angle: spec.argument, axis: [0, 1, 0])
            system.addChild(pivot)

            // The path, from the polar equation with the star at a FOCUS.
            let a = Float(spec.semiMajor), e = Float(spec.eccentricity)
            let semiLatus = a * (1 - e * e)
            let path = (0...96).map { step -> SIMD3<Float> in
                let nu = Float(step) / 96 * 2 * .pi
                let r = semiLatus / (1 + e * cos(nu))
                return SIMD3(r * cos(nu), 0, r * sin(nu))
            }
            if let track = line(path, radius: 0.0014, .white, opacity: 0.42) {
                pivot.addChild(track)
            }

            let planet = world(spec.name, radius: spec.size)
            // Tilted, so the texture's poles are off-axis and the thing
            // reads as a globe rather than as a flat disc.
            let tilt = simd_quatf(angle: 0.35,
                                  axis: simd_normalize(SIMD3(0.3, 1, 0.2)))
            planet.orientation = tilt
            pivot.addChild(planet)
            worlds.append((planet, spec.name))
            orbits.append(Orbit(
                planet: planet, tilt: tilt,
                semiMajor: spec.semiMajor, eccentricity: spec.eccentricity,
                period: basePeriod
                    * pow(spec.semiMajor / baseSemiMajor, 1.5)))
        }

        // The comet shows Kepler's second law at a glance — racing through
        // periapsis, crawling to apoapsis. Its nucleus is a modeled prop;
        // its tail stays procedural and points AWAY FROM THE SUN (not
        // behind the motion), growing as the ice nears boiling. Its
        // argument of periapsis spreads the e = 0.62 ellipse's reach onto
        // depth and height rather than a flat streak.
        let cometA: Float = 0.088, cometE: Float = 0.62
        let cometSemiLatus = cometA * (1 - cometE * cometE)
        let cometPivot = Entity()
        cometPivot.orientation = simd_quatf(angle: 2.27, axis: [0, 1, 0])
        system.addChild(cometPivot)
        let cometTrack = (0...96).map { step -> SIMD3<Float> in
            let nu = Float(step) / 96 * 2 * .pi
            let r = cometSemiLatus / (1 + cometE * cos(nu))
            return SIMD3(r * cos(nu), 0, r * sin(nu))
        }
        if let track = line(cometTrack, radius: 0.0011, .white, opacity: 0.30) {
            cometPivot.addChild(track)
        }
        let cometHolder = Entity()
        cometPivot.addChild(cometHolder)
        let rock = Entity()
        cometHolder.addChild(rock)
        if let nucleus = prop("CometNucleus", longest: 0.008) {
            rock.addChild(nucleus)
        } else {
            rock.addChild(ball(0.0030, UIColor(white: 0.35, alpha: 1), glow: 0.1))
        }
        var tailMaterial = UnlitMaterial(
            color: UIColor(red: 0.75, green: 0.88, blue: 1.0, alpha: 1))
        tailMaterial.blending = .transparent(opacity: 0.4)
        let tailBaseLength: Float = 0.02
        let tail = ModelEntity(
            mesh: .generateCone(height: tailBaseLength, radius: 0.0022),
            materials: [tailMaterial])
        cometHolder.addChild(tail)
        let tumbleAxis = simd_normalize(SIMD3<Float>(0.3, 1, 0.45))
        let cometPeriod = basePeriod * pow(Double(cometA) / baseSemiMajor, 1.5)

        let cycle = max(cometPeriod, orbits.map(\.period).max() ?? basePeriod)
        // CENTRED ON THE STAR, not on the box. The outer orbit is
        // genuinely eccentric and the star sits at its focus, so the
        // bounding box's middle is out in the empty half of the ellipse —
        // box-centring put the Sun a fifth of the way off-frame and hung
        // the exhibit's dead space in the middle of its bubble.
        return fit(root: root, frame: frame, cycle: cycle,
                   centredOn: .zero) { time in
            // A texture finished drawing: re-skin. `CelestialTextures`
            // renders off the main path, so the first frames of a fresh
            // launch really do have nothing to apply.
            if appliedTextureVersion != CelestialTextures.version {
                appliedTextureVersion = CelestialTextures.version
                for body in worlds {
                    body.entity.model?.materials = [celestialMaterial(body.name)]
                }
            }

            for orbit in orbits {
                let mean = 2 * Double.pi
                    * (time / orbit.period).truncatingRemainder(dividingBy: 1)
                let nu = trueAnomaly(meanAnomaly: mean,
                                     eccentricity: orbit.eccentricity)
                let semiLatus = orbit.semiMajor
                    * (1 - orbit.eccentricity * orbit.eccentricity)
                let r = Float(semiLatus / (1 + orbit.eccentricity * cos(nu)))
                orbit.planet.position = SIMD3(r * cos(Float(nu)), 0,
                                              r * sin(Float(nu)))
                // Spinning on its own axis, which is what makes a
                // textured sphere read as a world rather than as a
                // patterned bead.
                orbit.planet.orientation = orbit.tilt
                    * simd_quatf(angle: Float(time) * 0.8, axis: [0, 1, 0])
            }
            // The comet, by the same Kepler solve as the planets — and
            // the tail re-aimed anti-sunward every frame. The pivot is a
            // rotation about Y, so in its own frame the Sun is at the
            // origin and the radial direction is just the position.
            let cometMean = 2 * Double.pi
                * (time / cometPeriod).truncatingRemainder(dividingBy: 1)
            let cometNu = Float(trueAnomaly(meanAnomaly: cometMean,
                                            eccentricity: Double(cometE)))
            let cometR = cometSemiLatus / (1 + cometE * cos(cometNu))
            let local = SIMD3<Float>(cometR * cos(cometNu), 0,
                                     cometR * sin(cometNu))
            cometHolder.position = local
            let outward = simd_normalize(local)
            // Longer the closer the ice gets: sublimation scales hard
            // with insolation, so the length runs on r — near-nothing at
            // apoapsis, a real banner through periapsis.
            let tailLength = min(
                0.030, 0.016 * pow(cometA * (1 - cometE) / cometR, 1.2))
            // The cone's apex (+Y) is turned back toward the nucleus so
            // the tail widens and fades DOWNSTREAM.
            tail.orientation = rotation(from: [0, 1, 0], to: -outward)
            tail.position = outward * (tailLength / 2 + 0.002)
            let tailWidth = max(0.45, tailLength / tailBaseLength * 0.8)
            tail.scale = [tailWidth, tailLength / tailBaseLength, tailWidth]
            tail.components.set(OpacityComponent(
                opacity: min(1, tailLength / 0.012)))
            rock.orientation = simd_quatf(angle: Float(time) * 0.7,
                                          axis: tumbleAxis)

            // The star breathes, the way a light source should.
            corona.scale = SIMD3(repeating: 1 + 0.05 * Float(sin(time * 1.3)))
        }
    }

    // MARK: Circuits — a lit loop with charge going round it

    private static func circuits() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // A rounded rectangular loop of wire, near enough to square that
        // the fit does not have to squash it.
        let width: Float = 0.056, height: Float = 0.048
        func onLoop(_ t: Float) -> SIMD3<Float> {
            let angle = t * 2 * .pi
            // Superellipse: a rectangle with soft corners, in one line.
            let cx = cos(angle), sy = sin(angle)
            return SIMD3(width * sign(cx) * pow(abs(cx), 0.55),
                         height * sign(sy) * pow(abs(sy), 0.55), 0)
        }
        // Copper, not the near-black it used to be. That was the only
        // dark line in the file and it disappeared against a dark room —
        // the casing is what a line survives on now, not its own tint.
        if let wire = line((0...64).map { onLoop(Float($0) / 64) },
                           radius: 0.0021, DesignTokens.Palette.copperUI) {
            frame.addChild(wire)
        }

        // The battery and the bulb the workshop itself uses.
        let battery = prop("CircuitBattery", longest: 0.034) ?? {
            let box = ModelEntity(
                mesh: .generateBox(size: [0.030, 0.014, 0.014], cornerRadius: 0.004),
                materials: [Materials.energized(
                    UIColor(red: 0.24, green: 0.42, blue: 0.28, alpha: 1),
                    metallic: 0.7, glow: 0)])
            return box
        }()
        battery.position = [0, -height, 0]
        frame.addChild(battery)

        let bulbHolder = Entity()
        bulbHolder.position = [0, height, 0]
        frame.addChild(bulbHolder)
        if let bulb = prop("CircuitBulb", longest: 0.026) {
            bulbHolder.addChild(bulb)
        } else {
            bulbHolder.addChild(
                ball(0.013, UIColor(red: 1.0, green: 0.87, blue: 0.45, alpha: 1),
                     glow: 1))
        }
        var haloMaterial = UnlitMaterial(
            color: UIColor(red: 1, green: 0.88, blue: 0.5, alpha: 1))
        haloMaterial.blending = .transparent(opacity: 0.25)
        let halo = ModelEntity(mesh: .generateSphere(radius: 0.018),
                               materials: [haloMaterial])
        bulbHolder.addChild(halo)

        // The switch the workshop itself uses, spliced into the loop's
        // right side — the same asset the room loads, with the same
        // procedural lever `CircuitsRenderer` builds over it, because
        // the miniature is the map and the map's switch is the room's.
        // The lever is the moving part, so it is built HERE and captured
        // by the closure rather than pulled out of the asset by name.
        let switchScale: Float = 0.026 / 0.075   // miniature over room size
        let switchMount = Entity()
        switchMount.position = [width, 0, 0]
        switchMount.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        frame.addChild(switchMount)
        if let body = prop("CircuitSwitch", longest: 0.026) {
            switchMount.addChild(body)
        } else {
            switchMount.addChild(ModelEntity(
                mesh: .generateBox(size: [0.026, 0.006, 0.011],
                                   cornerRadius: 0.002),
                materials: [Materials.graphite(UIColor(white: 0.25, alpha: 1))]))
        }
        // The lever, at the same pivot the room's renderer puts it:
        // [-0.028, 0.008, 0] on the component's origin, arm reaching
        // +X — everything times the miniature's scale.
        let lever = Entity()
        lever.position = [-0.028 * switchScale, 0.008 * switchScale, 0]
        let arm = ModelEntity(
            mesh: .generateBox(size: [0.06 * switchScale, 0.008 * switchScale,
                                      0.014 * switchScale],
                               cornerRadius: 0.003 * switchScale),
            materials: [Materials.machined(UIColor(white: 0.75, alpha: 1),
                                           roughness: 0.3)])
        arm.position.x = 0.028 * switchScale
        lever.addChild(arm)
        switchMount.addChild(lever)

        // Charge carriers, evenly spaced round the loop. They used to lap
        // once every five and a half seconds, which reads as drift rather
        // than current.
        var carriers: [ModelEntity] = []
        for _ in 0..<10 {
            let dot = ModelEntity(
                mesh: .generateSphere(radius: 0.0030),
                materials: [Materials.energized(
                    DesignTokens.Palette.electronUI, glow: 0.9)])
            frame.addChild(dot)
            carriers.append(dot)
        }

        // The story is the switch. A loop of charge that never answers
        // to anything reads as decoration; current as the response to a
        // CLOSED PATH is this module's first teach, so the cycle is:
        // throw the switch, the carriers pull away and the filament
        // warms; open it, they coast to a stop and the room's light dies
        // with them. The carriers hold their places while stopped —
        // charge does not drain out of an open circuit.
        let period = 7.0
        let lapTime: Float = 2.9
        var progress: Float = 0
        var speed: Float = 0
        var leverAngle: Float = 0.62
        var lastTime = 0.0
        return fit(root: root, frame: frame, cycle: period) { time in
            let phase = time.truncatingRemainder(dividingBy: period)
            let closed = phase >= 0.9 && phase < 4.9
            let dt = Float(max(0, min(time - lastTime, 0.1)))
            lastTime = time

            leverAngle += ((closed ? 0 : 0.62) - leverAngle) * min(1, dt * 14)
            lever.orientation = simd_quatf(angle: leverAngle, axis: [0, 0, 1])

            // The current follows the switch with a short ease — not the
            // nanoseconds a real circuit takes, but the direction of
            // truth: the response belongs to the path being closed.
            speed += ((closed ? 1 : 0) - speed) * min(1, dt * 6)
            progress += dt * speed / lapTime
            for (index, carrier) in carriers.enumerated() {
                let t = (progress + Float(index) / Float(carriers.count))
                    .truncatingRemainder(dividingBy: 1)
                carrier.position = onLoop(t)
            }
            // The filament follows the current, not a clock.
            let glow = speed * (0.85 + 0.15 * Float(sin(time * 2.1)))
            halo.scale = SIMD3(repeating: 0.9 + glow * 0.28)
            halo.components.set(OpacityComponent(opacity: glow * 0.5))
        }
    }

    // MARK: Magnetism — two bars, forever almost snapping

    private static func magnetism() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        let halfLength: Float = 0.026
        let barLength = halfLength * 2

        /// A bar magnet: blue south at −X, red north at +X.
        ///
        /// That handedness is load-bearing and it is shared with
        /// `Tools/vignetteprops.py`, which authors the asset the same way
        /// round. Both bars are then placed UNFLIPPED, which is what puts
        /// the left one's north against the right one's south — the two
        /// facing poles have to be opposite or the motion below is an
        /// attraction between two poles that would actually shove each
        /// other apart.
        func magnet() -> Entity {
            let bar = Entity()
            if let modeled = prop("BarMagnet", longest: barLength) {
                bar.addChild(modeled)
                return bar
            }
            let half = MeshResource.generateBox(
                size: [halfLength, 0.013, 0.013], cornerRadius: 0.002)
            let south = ModelEntity(mesh: half, materials: [
                Materials.energized(
                    UIColor(red: 0.25, green: 0.47, blue: 0.95, alpha: 1),
                    glow: 0.25)])
            south.position.x = -halfLength / 2
            let north = ModelEntity(mesh: half, materials: [
                Materials.energized(
                    UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1),
                    glow: 0.25)])
            north.position.x = halfLength / 2
            bar.addChild(south)
            bar.addChild(north)
            return bar
        }

        let left = magnet()
        let right = magnet()
        frame.addChild(left)
        frame.addChild(right)

        // The compass, tilted up toward the reader, its needle aimed
        // every frame along the TRUE local field of the two bars — the
        // same magnetic-charge model the traced lines integrate, so the
        // needle and the lines cannot disagree. The needle ships as its
        // own asset (`Tools/moduleprops.py`) because it is the moving
        // part: the closure captures it directly, and it is authored
        // symmetric about its pivot so the importer's box-centring IS
        // the pivot.
        let compassTilt = simd_quatf(angle: 0.96, axis: [1, 0, 0])
        let compassAt = SIMD3<Float>(0, -0.056, 0.020)
        var needleHolder: Entity?
        if let bowl = prop("CompassBody", longest: 0.030) {
            let compass = Entity()
            compass.position = compassAt
            compass.orientation = compassTilt
            frame.addChild(compass)
            compass.addChild(bowl)
            if let needle = prop("CompassNeedle", longest: 0.021) {
                // Just clear of the dial furniture: the ticks top out
                // 0.0001 above the bowl's box centre and the needle is
                // 0.0011 thick at its cap.
                needle.position.y = 0.0012
                compass.addChild(needle)
                needleHolder = needle
            }
        }

        // Three traced field sets, one per stop of the approach, cross
        // faded as the gap changes.
        //
        // A field this close to its sources cannot be drawn once and
        // scaled: the lines are anchored to the poles, and the poles are
        // what move. Tracing at three gaps and blending between them
        // keeps every line attached to the metal it comes out of, and
        // the whole bundle is two draw calls per stop because `TubeMesh`
        // takes all the paths at once.
        let widest: Float = 0.044, closest: Float = 0.012
        func gap(at breath: Float) -> Float { widest + (closest - widest) * breath }

        func fieldSet(gap: Float) -> Entity? {
            let centre = halfLength + gap / 2
            let poles = [
                // Left bar: south outboard, north facing the gap.
                Pole(at: [-centre - halfLength, 0, 0], strength: -1),
                Pole(at: [-centre + halfLength, 0, 0], strength: 1),
                // Right bar: south facing the gap, north outboard.
                Pole(at: [centre - halfLength, 0, 0], strength: -1),
                Pole(at: [centre + halfLength, 0, 0], strength: 1),
            ]
            let southSinks: [(at: SIMD3<Float>, radius: Float)] = [
                (at: poles[0].at, radius: 0.010),
                (at: poles[2].at, radius: 0.010),
            ]
            let northSinks: [(at: SIMD3<Float>, radius: Float)] = [
                (at: poles[1].at, radius: 0.010),
                (at: poles[3].at, radius: 0.010),
            ]
            let reversedPoles = poles.map {
                Pole(at: $0.at, strength: -$0.strength)
            }

            // Seeded by FLUX: uniform angles around EVERY pole. Out of
            // both norths along the field; into both souths against it,
            // keeping only the lines that escape — a backward trace that
            // lands on a north is a line the forward pass already drew.
            // Seeding the norths alone drew every north-side line and
            // only the south-side lines that happened to connect, so the
            // outboard south ends sat visibly barer than the norths —
            // the field of two equal bars is even and the picture
            // wasn't. Hand-picked tilts are gone for the same reason:
            // uniform angles are what equal flux per line means.
            var paths: [[SIMD3<Float>]] = []
            let tiltCount = 3
            func fan(_ source: SIMD3<Float>, along: Float,
                     trace: (SIMD3<Float>) -> Void) {
                for roll in [Float(0), .pi / 2] {
                    for index in 0..<tiltCount {
                        let tilt = (Float(index) + 0.5) * .pi / Float(tiltCount)
                        for flip in [Float(1), -1] {
                            let out = SIMD3<Float>(cos(tilt) * along,
                                                   sin(tilt) * cos(roll) * flip,
                                                   sin(tilt) * sin(roll) * flip)
                            trace(source + out * 0.0085)
                        }
                    }
                }
            }
            // Cut short. A dipole's outermost lines run a long way for
            // very little, and `fit` measures every millimetre of them —
            // at an escape radius of 0.11 the far tails were half the
            // exhibit's width, so the magnets themselves were scaled
            // down to a third of their bubble and the thing the module
            // is ABOUT became the small part.
            for north in [poles[1].at, poles[3].at] {
                fan(north, along: north.x < 0 ? 1 : -1) { seed in
                    let path = fieldLine(from: seed, poles: poles,
                                         step: 0.0022, escape: 0.072,
                                         sinks: southSinks)
                    if path.count > 3 { paths.append(path) }
                }
            }
            for south in [poles[0].at, poles[2].at] {
                fan(south, along: south.x < 0 ? -1 : 1) { seed in
                    let path = fieldLine(from: seed,
                                         poles: reversedPoles,
                                         step: 0.0022, escape: 0.072,
                                         sinks: northSinks)
                    guard path.count > 3, let far = path.last,
                          northSinks.allSatisfy({
                              simd_distance(far, $0.at) > $0.radius + 0.002
                          }) else { return }
                    paths.append(path.reversed())
                }
            }
            // The magnet's own lavender (`MagnetismRenderer.lineColor`),
            // NOT the electric field's token — reading the renderer's own
            // constant keeps miniature and apparatus from drifting apart.
            return lines(paths, radius: 0.0017,
                         MagnetismRenderer.lineColor)
        }

        let stops: [Float] = [0, 0.5, 1]
        var sets: [(entity: Entity, stop: Float)] = []
        for stop in stops {
            guard let set = fieldSet(gap: gap(at: stop)) else { continue }
            frame.addChild(set)
            sets.append((set, stop))
        }

        let period = 5.7
        var needleAngle: Float = 0
        var lastTime = 0.0
        return fit(root: root, frame: frame, cycle: period) { time in
            // The approach, the almost-snap, the ease apart — the pull
            // between opposite poles as a loop of motion. The gap never
            // quite closes: a snap that lands would need a jolt, and a
            // jolt on a loop reads as a glitch.
            let breath = Float((1 - cos(2 * .pi * time / period)) / 2)
            let centre = halfLength + gap(at: breath) / 2
            left.position.x = -centre
            right.position.x = centre
            for set in sets {
                // A linear tent over the three stops: the weights always
                // sum to one, so the bundle never dims in the crossover.
                let weight = max(0, 1 - abs(breath - set.stop) / 0.5)
                set.entity.components.set(
                    OpacityComponent(opacity: weight * (0.45 + 0.5 * breath)))
            }

            // The needle: evaluate the four moving poles at the compass,
            // project the field onto the tilted dial, and steer toward
            // it with a little lag — a real needle has inertia, and an
            // instantaneous one reads as painted on.
            if let needle = needleHolder {
                let poles = [
                    Pole(at: [-centre - halfLength, 0, 0], strength: -1),
                    Pole(at: [-centre + halfLength, 0, 0], strength: 1),
                    Pole(at: [centre - halfLength, 0, 0], strength: -1),
                    Pole(at: [centre + halfLength, 0, 0], strength: 1),
                ]
                if let field = fieldDirection(at: compassAt, poles: poles) {
                    let planar = compassTilt.inverse.act(field)
                    let target = atan2(-planar.z, planar.x)
                    let dt = Float(max(0, min(time - lastTime, 0.1)))
                    var delta = target - needleAngle
                    while delta > .pi { delta -= 2 * .pi }
                    while delta < -.pi { delta += 2 * .pi }
                    needleAngle += delta * min(1, dt * 9)
                    needle.orientation = simd_quatf(angle: needleAngle,
                                                    axis: [0, 1, 0])
                }
                lastTime = time
            }
        }
    }

    // MARK: Pendulums — two beating against each other, one in 3-D

    private static func pendulums() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // The precision stand from `Tools/moduleprops.py`: cast base,
        // two columns, a crossbeam carrying three clevis pivots. All the
        // numbers below are that file's, mapped through one scale — the
        // importer normalises the longest dimension, the 0.400 beam, and
        // centres the authored box (z -0.006...0.2652, pins at 0.2355,
        // pivots at x 0 and ±0.124).
        let standWidth: Float = 0.148
        let standScale = standWidth / 0.400
        let pivotY: Float = 0.052
        let pivotXs: [Float] = [-0.124 * standScale, 0, 0.124 * standScale]
        if let stand = prop("PendulumStand", longest: standWidth) {
            let boxCentre: Float = (0.2652 - 0.006) / 2
            stand.position.y = pivotY - (0.2355 - boxCentre) * standScale
            frame.addChild(stand)
        } else {
            let beam = ModelEntity(
                mesh: .generateBox(size: [standWidth, 0.006, 0.010],
                                   cornerRadius: 0.003),
                materials: [Materials.energized(UIColor(white: 0.62, alpha: 1),
                                                metallic: 1, glow: 0)])
            beam.position.y = pivotY
            frame.addChild(beam)
        }

        /// A pendulum: a taut cable and a turned-brass bob, both hanging
        /// off a pivot whose ORIENTATION is the whole state. Rotating the
        /// pivot keeps the cable straight without ever remeshing it.
        ///
        /// The bob hangs by its EYE — authored 0.02265 above its own box
        /// centre in a 0.0537 span — so the holder is pushed down until
        /// the eye lands on the cable's end.
        func hang(at x: Float, length: Float) -> Entity {
            let pivot = Entity()
            pivot.position = [x, pivotY, 0]
            frame.addChild(pivot)
            if let cable = line([[0, 0, 0], [0, -length, 0]], radius: 0.0009,
                                UIColor(white: 0.68, alpha: 1)) {
                pivot.addChild(cable)
            }
            let bobSpan: Float = 0.0255
            if let bob = prop("PendulumBob", longest: bobSpan) {
                bob.position.y = -length - 0.02265 * (bobSpan / 0.0537)
                pivot.addChild(bob)
            } else {
                let bob = ball(0.0095, DesignTokens.Palette.pendulumsAccentUI,
                               glow: 0.15)
                bob.position.y = -length
                pivot.addChild(bob)
            }
            return pivot
        }

        // Two lengths a few per cent apart: they leave together, drift
        // out of step and re-align. Real pendulum timing, so T grows as
        // the square root of the length. The lengths are bounded by the
        // apparatus now: the longest cable plus its bob must clear the
        // base plate, which tops out 0.083 under the pins.
        let planarLengths: [Float] = [0.044, 0.054]
        var planar: [(pivot: Entity, period: Double)] = []
        for (index, length) in planarLengths.enumerated() {
            let pivot = hang(at: pivotXs[index * 2], length: length)
            planar.append((pivot, Double(length.squareRoot()) * 6.2))
        }

        // And the middle one does what the module actually promises: a
        // true three-dimensional orbit. A spherical pendulum released off
        // axis traces an ellipse that slowly precesses, and every bob in
        // this miniature used to swing in the same flat plane instead.
        let orbitLength: Float = 0.049
        let orbiter = hang(at: 0, length: orbitLength)
        let orbitPeriod = Double(orbitLength.squareRoot()) * 6.2

        let cycle = 24.0
        return fit(root: root, frame: frame, cycle: cycle) { time in
            for swing in planar {
                let angle = 0.40 * sin(2 * .pi * time / swing.period)
                swing.pivot.orientation = simd_quatf(angle: Float(angle),
                                                     axis: [0, 0, 1])
            }

            // The orbit, as a direction for the cable to point down.
            let sweep = 2 * .pi * time / orbitPeriod
            let precession = Float(time) * 0.20
            let a: Float = 0.40, b: Float = 0.19
            var offset = SIMD3<Float>(a * Float(sin(sweep)), 0,
                                      b * Float(cos(sweep)))
            offset = SIMD3(
                offset.x * cos(precession) - offset.z * sin(precession), 0,
                offset.x * sin(precession) + offset.z * cos(precession))
            let drop = sqrt(max(1 - simd_length_squared(offset), 0.05))
            let direction = simd_normalize(SIMD3(offset.x, -drop, offset.z))
            orbiter.orientation = rotation(from: [0, -1, 0], to: direction)
        }
    }

    // MARK: Labs — the gyroscope that opens the ring

    /// The bead's gyroscope: an instrument belonging to no single lab,
    /// meaning what the bead means — the thing that holds still while
    /// everything turns. Assembled from three separate assets so the
    /// closure can capture each moving part directly (not named children
    /// of one model). When the ring opens, the gimbals lay flat into the arc.
    private static func gyroscope() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        // A third level, beneath the frame. `fit` owns `frame.scale`, and
        // the unfold below needs a scale of its own — writing it to the
        // frame reset the fit and the emblem came back a different size
        // every time the ring shut.
        let unfold = Entity()
        frame.addChild(unfold)

        let outerRadius: Float = 0.080

        func gimbal(_ name: String, radius: Float) -> Entity {
            if let modeled = prop(name, longest: radius * 2) { return modeled }
            let holder = Entity()
            let points = (0...64).map { step -> SIMD3<Float> in
                let angle = Float(step) / 64 * 2 * .pi
                return SIMD3(cos(angle) * radius, sin(angle) * radius, 0)
            }
            if let hoop = line(points, radius: radius * 0.045,
                               UIColor(red: 0.78, green: 0.66, blue: 0.36, alpha: 1)) {
                holder.addChild(hoop)
            }
            return holder
        }

        // Outer ring: the one bolted to the case, upright.
        let outer = gimbal("GyroGimbalOuter", radius: outerRadius)
        unfold.addChild(outer)

        // Inner ring: hung inside the outer one, at ninety degrees.
        let innerPivot = Entity()
        outer.addChild(innerPivot)
        let inner = gimbal("GyroGimbalInner", radius: outerRadius * 0.74)
        inner.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        innerPivot.addChild(inner)

        // The rotor, and the axle it is heavy on.
        let rotorPivot = Entity()
        innerPivot.addChild(rotorPivot)
        let rotor: Entity
        if let modeled = prop("GyroRotor", longest: outerRadius * 1.25) {
            rotor = modeled
        } else {
            let disc = ModelEntity(
                mesh: .generateCylinder(height: outerRadius * 0.16,
                                        radius: outerRadius * 0.53),
                materials: [Materials.machined(UIColor(white: 0.74, alpha: 1),
                                               roughness: 0.3)])
            disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            rotor = disc
        }
        rotorPivot.addChild(rotor)

        var openness: Float = 0

        let cycle = 4.0
        return fit(root: root, frame: frame, cycle: cycle, animate: { time in
            // The rotor never stops. Everything else in this app pauses;
            // the thing you navigate with does not.
            rotorPivot.orientation = simd_quatf(angle: Float(time) * 3.1,
                                                axis: [0, 0, 1])
            // The gimbals hold the rotor level against the bead's own
            // breathing — which is what a gimbal is FOR, and reads as an
            // uncanny stillness at the centre of a moving object.
            let lean = 0.16 * Float(sin(time * 0.9))
            outer.orientation = simd_quatf(angle: lean, axis: [0, 1, 0])
            innerPivot.orientation = simd_quatf(angle: -lean * 0.8 + openness * 1.2,
                                                axis: [1, 0, 0])
        }, setOpenness: { value in
            openness = value
            // Opening flattens the rings toward the plane the labs fan
            // across, and draws the emblem back so the miniatures coming
            // out of it are not competing with a spinning brass object.
            unfold.scale = SIMD3(repeating: 1 - 0.30 * value)
        })
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
