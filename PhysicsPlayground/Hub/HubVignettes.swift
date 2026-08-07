//
//  HubVignettes.swift
//  Physics Playground — Hub
//
//  The miniatures in the hub gallery and the labs ring, and what each of
//  them DOES.
//
//  They used to come from nine Blender assets authored months apart, in
//  nine different styles and at nine different levels of finish — a
//  spiky ball for the electric field, a stack of coloured tiles for the
//  drumhead — and they were static. Worse, the "live exhibit" animation
//  added later matched children by NAME, and those names only existed in
//  the procedural fallbacks; every module that loaded an asset silently
//  never animated at all.
//
//  So: one file, one visual language, each miniature returning its own
//  animation closure alongside the geometry it drives. A model and its
//  motion can no longer drift apart, because they are written in the
//  same place and the closure captures the very entities it moves — no
//  name lookups, no per-frame tree searches.
//
//  Assets came back after that, on those terms. A few of these
//  miniatures load the SAME usdz the room loads — the launcher barrel,
//  the battery, the bulb — because the miniature is the map you arrive
//  holding, and a map drawn from different geometry than the place is
//  worse than none. They are static props parented under entities the
//  closure moves, so the failure above cannot recur: nothing is looked
//  up, and nothing loaded is asked to flex. The things that must flex —
//  field lines, the trajectory, the orbits, the wire loop, the cables —
//  stay procedural for exactly that reason.
//
//  Three rules hold the file together:
//
//  1. A vignette NEVER writes its own root transform. That belongs to
//     whoever placed it. All content hangs off an inner `frame`.
//  2. `fit` owns `frame.position` and `frame.scale`. An animation that
//     needs a scale of its own gets a third level beneath the frame.
//  3. Every drawn line goes through `lines(_:)`, which puts the design
//     system's two passes — dark casing, bright core — on all of them.
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

    /// Centres `frame` on the root's origin and normalises it to the
    /// common square, measuring across a whole cycle of the motion
    /// rather than at rest.
    ///
    /// Both hosts measure ONCE, at build time, before a single frame has
    /// run. So a miniature whose motion carries it outside its resting
    /// bounds is fitted from a box smaller than the one it actually
    /// uses, and overflows its bubble — which is precisely what the
    /// projectile did: its strobe dots and its ball are created at the
    /// origin and only reach the arc on the first `animate`, so the fit
    /// never saw the trajectory at all.
    ///
    /// Neither host consults the bounds CENTRE either, only the extents,
    /// so whatever origin a builder happened to author to became the
    /// middle of the bubble. The pendulum rig hung entirely in the upper
    /// half of its own slot for that reason.
    ///
    /// Sampling is also what retires the hand-picked "widest pose"
    /// offsets the magnets and the spring used to carry. Both of those
    /// comments were describing this function's job.
    ///
    /// `centredOn` overrides which point lands in the middle. Almost
    /// every miniature wants the middle of its own bounding box, which is
    /// the default — but a solar system does not: its star sits at a
    /// FOCUS of the ellipses, not at their centre, so box-centring pushed
    /// the one thing the eye goes to a fifth of the way off-frame while
    /// the empty far end of the orbit took the middle. Where an exhibit
    /// has an obvious anchor, that anchor is the centre.
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

        // Half-extents measured OUTWARD FROM THE CENTRE, taking the
        // larger side. With a box centre those two sides are equal and
        // this is the plain span; with an anchor off to one side it is
        // what keeps the long side inside the square instead of letting
        // it hang out.
        let centre = pivot ?? (lower + upper) / 2
        let reach = simd_max(upper - centre, centre - lower)
        let span = max(reach.x, max(reach.y, 1e-4)) * 2
        let scale = frameHalf * 2 / span
        // The frame's own scale applies to the centre we just measured,
        // so the offset that lands it on the origin is the SCALED centre
        // negated — not the raw one.
        frame.scale = SIMD3(repeating: scale)
        frame.position = -centre * scale

        // And the square itself, as an invisible box on the ROOT where no
        // animation can reach it.
        //
        // Normalising the swept union is not enough on its own, because
        // the hosts measure at REST and a miniature at rest is smaller
        // than the same miniature mid-swing — the pendulum rig came out
        // 0.139 against the gravity system's 0.165, so each was still
        // handed a different number to divide by and the streak this
        // whole contract exists to prevent survived. The proxy makes the
        // measurement independent of the pose: every miniature reports
        // exactly one square, whatever it happens to be doing at the
        // instant somebody looks at it.
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

    /// A bundle of drawn lines, in the two passes the design system asks
    /// for: a near-black casing swept fatter than the bright core.
    ///
    /// `Materials.contrastLine` shipped in four module renderers and in
    /// NONE of these miniatures, which is why every one of them dissolved
    /// against a bright wall. Passthrough is a bright medium; a 2 mm cyan
    /// tube at 0.9 opacity has nothing to be bright against, and the
    /// exhibit fit then magnifies it about twofold. Putting both passes
    /// inside the one helper every arc, ring, cable and orbit already
    /// goes through is what makes the whole file inherit them.
    ///
    /// All the paths share ONE mesh per pass — `TubeMesh` takes a list of
    /// polylines — so a sixteen-line field bundle is two draw calls, not
    /// thirty-two.
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

    /// One loaded prototype per asset; every use gets a clone. Same
    /// arrangement `CircuitsRenderer.modeledBody` uses, for the same
    /// reason: `Entity.load` is synchronous, and the gallery builds every
    /// exhibit in a single pass.
    ///
    /// Failures are cached too. A missing asset should cost one failed
    /// load, not one per exhibit per rebuild — and every call site below
    /// keeps the geometry it used to draw as its fallback, so a miniature
    /// degrades instead of vanishing.
    private static var prototypes: [String: Entity?] = [:]

    /// A prop, centred on its own origin and scaled so its longest
    /// dimension is `longest`.
    ///
    /// Measured rather than assumed: these assets were authored at real
    /// bench sizes, and a miniature has no business knowing which of them
    /// happens to be 30 cm long.
    private static func prop(_ name: String, longest: Float) -> Entity? {
        if prototypes[name] == nil {
            prototypes[name] = try? Entity.load(named: name)
        }
        guard let prototype = prototypes[name] ?? nil else { return nil }

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
        let positive = ball(chargeRadius, DesignTokens.Palette.positiveUI, glow: 0.6)
        let negative = ball(chargeRadius, DesignTokens.Palette.negativeUI, glow: 0.6)
        positive.position.x = -separation
        negative.position.x = separation
        frame.addChild(positive)
        frame.addChild(negative)

        // The signs, so a glance says "dipole" and not "two dots".
        let barMesh = MeshResource.generateBox(size: [0.016, 0.0038, 0.0038],
                                               cornerRadius: 0.0019)
        let signMaterial = UnlitMaterial(color: .white)
        for (parent, vertical) in [(positive, true), (negative, false)] {
            let across = ModelEntity(mesh: barMesh, materials: [signMaterial])
            across.position.z = chargeRadius - 0.001
            parent.addChild(across)
            if vertical {
                let up = ModelEntity(mesh: barMesh, materials: [signMaterial])
                up.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                up.position.z = chargeRadius - 0.001
                parent.addChild(up)
            }
        }

        let poles = [Pole(at: [-separation, 0, 0], strength: 1),
                     Pole(at: [separation, 0, 0], strength: -1)]
        let sinks = [(at: SIMD3<Float>(separation, 0, 0),
                      radius: chargeRadius + 0.001)]

        // Seeded evenly in polar angle on the + charge's surface, in two
        // perpendicular planes. The steep seeds close onto the −; the
        // ones aimed backwards run off to the escape radius and are cut,
        // which is what a real dipole does and what the four hand-drawn
        // cosine arcs could never show.
        var paths: [[SIMD3<Float>]] = []
        for roll in [Float(0), .pi / 2] {
            for tilt in [Float(0.42), 0.95, 1.55, 2.15] {
                for flip in [Float(1), -1] {
                    let out = SIMD3<Float>(cos(tilt),
                                           sin(tilt) * cos(roll) * flip,
                                           sin(tilt) * sin(roll) * flip)
                    let seed = SIMD3<Float>(-separation, 0, 0)
                        + out * (chargeRadius + 0.0015)
                    let path = fieldLine(from: seed, poles: poles,
                                         step: 0.0022, escape: 0.088,
                                         sinks: sinks)
                    if path.count > 3 { paths.append(path) }
                    if roll == 0 && (tilt == 0.42 || tilt == 2.15) { break }
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
        let base = ModelEntity(
            mesh: .generateCylinder(height: reach * 0.062,
                                    radius: reach * 0.085),
            materials: [Materials.machined(UIColor(white: 0.55, alpha: 1),
                                           roughness: 0.4)])
        base.position.y = -reach * 0.031
        frame.addChild(base)

        // The hoop, where the real arc actually lands — so the target is
        // a consequence of the physics rather than a decision.
        let landing = flown.last?.at ?? .zero
        if let hoop = ring(radius: reach * 0.095, tube: reach * 0.012,
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

        let sun = world("Sun", radius: 0.015)
        system.addChild(sun)
        var coronaMaterial = UnlitMaterial(color: DesignTokens.Palette.celestialUI("Sun"))
        coronaMaterial.blending = .transparent(opacity: 0.22)
        let corona = ModelEntity(mesh: .generateSphere(radius: 0.024),
                                 materials: [coronaMaterial])
        system.addChild(corona)

        /// True anomaly from mean anomaly, by Newton on Kepler's
        /// equation. Five iterations is convergence to well under a
        /// pixel at this eccentricity, and it is the whole reason the
        /// outer planet visibly races at periapsis and crawls at
        /// apoapsis instead of sliding round at a constant rate.
        func trueAnomaly(meanAnomaly: Double, eccentricity: Double) -> Double {
            var E = meanAnomaly
            for _ in 0..<5 {
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

        // Two worlds, and their periods obey Kepler's third law: the
        // outer one is not just slower, it is slower by exactly
        // (a₂/a₁)^³ᐟ².
        //
        // `argument` is the argument of periapsis — where in the plane
        // the orbit's long axis points, and a real orbital element that
        // the lab itself computes. Here it also does compositional work:
        // an eccentric orbit reaches further on one side than the other,
        // and with both long axes pointing the same way all of that
        // overhang piled onto one edge of the square. Turning the outer
        // one across the frame spreads its reach over both axes, so a
        // star-centred exhibit still fills its bubble.
        let plan: [(semiMajor: Double, eccentricity: Double, argument: Float,
                    name: String, size: Float)] = [
            (0.042, 0.10, 0, "Earth", 0.0080),
            (0.072, 0.30, 2.2, "Mars", 0.0064),
        ]
        let baseSemiMajor = plan[0].semiMajor
        let basePeriod = 5.2

        for spec in plan {
            let pivot = Entity()
            pivot.orientation = simd_quatf(angle: spec.argument, axis: [0, 1, 0])
            system.addChild(pivot)

            // The path, from the polar equation with the star at a FOCUS
            // — which is where the star of an elliptical orbit is, and
            // the reason the outer world swings close on one side.
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

        let cycle = orbits.map(\.period).max() ?? basePeriod
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

        let period = 2.9
        return fit(root: root, frame: frame, cycle: period) { time in
            for (index, carrier) in carriers.enumerated() {
                let t = Float((time / period
                               + Double(index) / Double(carriers.count))
                    .truncatingRemainder(dividingBy: 1))
                carrier.position = onLoop(t)
            }
            // The filament breathes as if the supply were alive.
            let glow = 0.78 + 0.22 * Float(sin(time * 2.1))
            halo.scale = SIMD3(repeating: 0.9 + glow * 0.22)
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
            let sinks: [(at: SIMD3<Float>, radius: Float)] = [
                (at: poles[0].at, radius: 0.010),
                (at: poles[2].at, radius: 0.010),
            ]

            // Seeded on BOTH norths. Tracing only the left magnet's put
            // every line on one side of the picture: correct as far as
            // it went — those really are field lines — but it read as one
            // magnet doing all the work and another sitting next to it.
            // A field between two magnets is symmetric, and the exhibit
            // should look it.
            var paths: [[SIMD3<Float>]] = []
            for source in [poles[1].at, poles[3].at] {
                let outward: Float = source.x < 0 ? 1 : -1
                for roll in [Float(0), .pi / 2] {
                    for tilt in [Float(0.5), 1.05, 1.62, 2.2] {
                        for flip in [Float(1), -1] {
                            let out = SIMD3<Float>(cos(tilt) * outward,
                                                   sin(tilt) * cos(roll) * flip,
                                                   sin(tilt) * sin(roll) * flip)
                            let seed = source + out * 0.0085
                            // Cut short. A dipole's outermost lines run a
                            // long way for very little, and `fit` measures
                            // every millimetre of them — at an escape
                            // radius of 0.11 the far tails were half the
                            // exhibit's width, so the magnets themselves
                            // were scaled down to a third of their bubble
                            // and the thing the module is ABOUT became
                            // the small part.
                            let path = fieldLine(from: seed, poles: poles,
                                                 step: 0.0022, escape: 0.072,
                                                 sinks: sinks)
                            if path.count > 3 { paths.append(path) }
                        }
                    }
                }
            }
            return lines(paths, radius: 0.0017,
                         DesignTokens.Palette.fieldLineUI)
        }

        let stops: [Float] = [0, 0.5, 1]
        var sets: [(entity: Entity, stop: Float)] = []
        for stop in stops {
            guard let set = fieldSet(gap: gap(at: stop)) else { continue }
            frame.addChild(set)
            sets.append((set, stop))
        }

        let period = 5.7
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
        }
    }

    // MARK: Pendulums — two beating against each other, one in 3-D

    private static func pendulums() -> Built {
        let root = Entity()
        let frame = Entity()
        root.addChild(frame)

        let span: Float = 0.115
        let beamY: Float = 0.052
        if let gantry = prop("PendulumGantry", longest: span) {
            gantry.position.y = beamY - span * 0.16
            frame.addChild(gantry)
        } else {
            let beam = ModelEntity(
                mesh: .generateBox(size: [span, 0.006, 0.010], cornerRadius: 0.003),
                materials: [Materials.energized(UIColor(white: 0.62, alpha: 1),
                                                metallic: 1, glow: 0)])
            beam.position.y = beamY
            frame.addChild(beam)
        }

        /// A pendulum: a taut cable and a bob, both hanging off a pivot
        /// whose ORIENTATION is the whole state. Rotating the pivot keeps
        /// the cable straight without ever remeshing it.
        func hang(at x: Float, length: Float) -> Entity {
            let pivot = Entity()
            pivot.position = [x, beamY - 0.004, 0]
            frame.addChild(pivot)
            if let cable = line([[0, 0, 0], [0, -length, 0]], radius: 0.0009,
                                UIColor(white: 0.68, alpha: 1)) {
                pivot.addChild(cable)
            }
            let bob = ball(0.0095, DesignTokens.Palette.pendulumsAccentUI, glow: 0.15)
            bob.position.y = -length
            pivot.addChild(bob)
            return pivot
        }

        // Two lengths a few per cent apart: they leave together, drift
        // out of step and re-align. Real pendulum timing, so T grows as
        // the square root of the length.
        let planarLengths: [Float] = [0.072, 0.088]
        var planar: [(pivot: Entity, period: Double)] = []
        for (index, length) in planarLengths.enumerated() {
            let pivot = hang(at: (Float(index) * 2 - 1) * 0.036, length: length)
            planar.append((pivot, Double(length.squareRoot()) * 6.2))
        }

        // And the middle one does what the module actually promises: a
        // true three-dimensional orbit. A spherical pendulum released off
        // axis traces an ellipse that slowly precesses, and every bob in
        // this miniature used to swing in the same flat plane instead.
        let orbitLength: Float = 0.080
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

    /// The app's only permanent piece of interface, and until now a white
    /// glass sphere with an SF Symbol grid floating in it — iOS chrome on
    /// the one object that is never not on screen.
    ///
    /// A gyroscope instead. It belongs to no single lab, which an
    /// armillary would not (that reads as Gravity Lab's property); it is
    /// an instrument rather than an icon, which is the language every
    /// other object in this app speaks; and its meaning is exactly the
    /// bead's job — the thing that holds still while everything around it
    /// turns. When the ring opens, the gimbals unlock and lay flat into
    /// the arc the labs fan along.
    ///
    /// Assembled from three separate assets rather than one, so the
    /// closure can capture each moving part directly. Pulling named
    /// children out of a single loaded model is the exact mistake this
    /// file was rewritten to end.
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
