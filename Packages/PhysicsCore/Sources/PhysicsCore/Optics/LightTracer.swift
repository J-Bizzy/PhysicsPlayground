//
//  LightTracer.swift
//  PhysicsCore — Optics
//
//  Light through optics that stand anywhere in a room at any pose:
//  mirrors, prisms, lenses and blocks, each with a position and an
//  orientation, and the room's own walls and floor for the light to land
//  on. Nothing here assumes an optical axis or a bench — that assumption
//  is why the first optics lab was archived.
//
//  The physics is exact geometric optics:
//    - every surface is met exactly (planes, spheres, a cylinder; no
//      tessellation), so a lens's spherical aberration is real, not
//      modelled;
//    - refraction is Snell's law in vector form (`Refraction.refract`);
//    - every glass surface splits the light, reflecting the Fresnel
//      fraction for unpolarised light and transmitting the rest, and
//      past the critical angle reflects all of it;
//    - each wavelength is traced on its own through the glass's
//      Sellmeier index, so dispersion comes out of the trace rather than
//      being painted on;
//    - power is accounted for: what lands, what a mirror absorbs, what
//      meets nothing and what was too faint to follow always sum to what
//      the sources emitted.
//
//  Each glass element is a convex solid, the intersection of a few
//  primitives (half-spaces, balls, a cylinder). A ray meets a convex
//  solid on one interval, entered through the primitive whose entry is
//  latest and left through the one whose exit is earliest — so one
//  routine serves the prism, the block and the lens.
//
//  Metres, nanometres, radians.
//

import Foundation
import simd

/// One piece of optics in the room.
public struct OpticalElement: Sendable, Equatable, Identifiable {
    public enum Shape: Sendable, Equatable {
        /// A front-silvered disc in the element's local xy-plane. Light
        /// arriving on its +z face reflects (losing 1 − `reflectance`);
        /// light arriving from behind is absorbed by the backing.
        case mirror(radius: Double, reflectance: Double)
        /// An isosceles triangular prism. Its cross-section lies in the
        /// local xy-plane with the apex (angle `apexAngle`, between the
        /// two faces of length `side`) toward +y and the base toward −y,
        /// centred on the triangle's centroid; it runs `length` along z.
        case prism(apexAngle: Double, side: Double, length: Double)
        /// A converging lens on the local z-axis: a front face bulging
        /// toward −z with radius `frontRadius` and a back face bulging
        /// toward +z with radius `backRadius` (`.infinity` for a flat
        /// face), `thickness` apart at the centre, cut to `diameter`.
        case lens(frontRadius: Double, backRadius: Double, thickness: Double, diameter: Double)
        /// A rectangular block.
        case block(halfExtents: SIMD3<Double>)
    }

    public var id: UUID
    public var position: SIMD3<Double>
    public var orientation: simd_quatd
    public var shape: Shape
    /// What the element is made of. A mirror ignores it.
    public var glass: Glass

    public init(id: UUID = UUID(), position: SIMD3<Double>,
                orientation: simd_quatd = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1),
                shape: Shape, glass: Glass = .nbk7) {
        self.id = id
        self.position = position
        self.orientation = orientation
        self.shape = shape
        self.glass = glass
    }

    public func toWorld(point p: SIMD3<Double>) -> SIMD3<Double> {
        position + orientation.act(p)
    }

    public func toWorld(direction d: SIMD3<Double>) -> SIMD3<Double> {
        orientation.act(d)
    }

    public func toLocal(point p: SIMD3<Double>) -> SIMD3<Double> {
        orientation.inverse.act(p - position)
    }

    public func toLocal(direction d: SIMD3<Double>) -> SIMD3<Double> {
        orientation.inverse.act(d)
    }

    /// The prism's three corners in its local cross-section (apex, then
    /// the two base corners), for anything that draws or tests it.
    public static func prismCorners(apexAngle: Double, side: Double) -> [SIMD2<Double>] {
        let halfBase = side * sin(apexAngle / 2)
        let height = side * cos(apexAngle / 2)
        return [SIMD2(0, 2 * height / 3),
                SIMD2(-halfBase, -height / 3),
                SIMD2(halfBase, -height / 3)]
    }
}

public enum LightTracer {

    // MARK: What goes in

    /// Light leaving a source: one wavelength along one line.
    public struct Ray: Sendable, Equatable {
        public var origin: SIMD3<Double>
        public var direction: SIMD3<Double>
        public var nanometers: Double
        /// Watts, or any unit — the trace is linear in it.
        public var power: Double

        public init(origin: SIMD3<Double>, direction: SIMD3<Double>,
                    nanometers: Double, power: Double = 1) {
            self.origin = origin
            self.direction = simd_normalize(direction)
            self.nanometers = nanometers
            self.power = power
        }
    }

    /// The room the light lands in: the walls ARKit has found (and the
    /// scanned bounds), and the floor.
    public struct Room: Sendable, Equatable {
        public var walls: [RoomWalls.Wall]
        /// The floor's height, or nil to let light fall forever.
        public var floorY: Double?
        /// How far light may travel in one straight line before it is
        /// counted as having met nothing.
        public var maxSegment: Double

        public init(walls: [RoomWalls.Wall] = [], floorY: Double? = nil,
                    maxSegment: Double = 12) {
            self.walls = walls
            self.floorY = floorY
            self.maxSegment = maxSegment
        }

        public static let open = Room()
    }

    public struct Options: Sendable, Equatable {
        /// Follow the weak reflections a glass surface makes (about 4 %
        /// each). Off, they are counted as unfollowed (`dropped`).
        public var followsPartialReflections: Bool
        /// A branch fainter than this fraction of its source ray's power
        /// is not followed further.
        public var minFraction: Double
        /// The most surfaces one path may meet.
        public var maxDepth: Int

        public init(followsPartialReflections: Bool = true,
                    minFraction: Double = 0.01, maxDepth: Int = 24) {
            self.followsPartialReflections = followsPartialReflections
            self.minFraction = minFraction
            self.maxDepth = maxDepth
        }
    }

    // MARK: What comes out

    /// One straight stretch of light.
    public struct Segment: Sendable, Equatable {
        public var a: SIMD3<Double>
        public var b: SIMD3<Double>
        public var nanometers: Double
        public var power: Double
        /// The element whose glass this stretch runs through, if any.
        public var inside: UUID?

        public var direction: SIMD3<Double> { simd_normalize(b - a) }
    }

    /// Light arriving at the room.
    public struct Landing: Sendable, Equatable {
        public enum Surface: Sendable, Equatable { case wall(Int), floor }
        public var point: SIMD3<Double>
        /// The surface normal, turned to face the light.
        public var normal: SIMD3<Double>
        public var direction: SIMD3<Double>
        public var nanometers: Double
        public var power: Double
        public var surface: Surface
    }

    /// Light meeting an element's surface.
    public struct Event: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// Off a mirror's face (or absorbed by its back: `reflectance` 0).
            case mirror
            /// From air into glass.
            case enter
            /// From glass into air.
            case exit
            /// From glass toward air, past the critical angle.
            case totalInternalReflection
        }
        public var element: UUID
        public var kind: Kind
        public var point: SIMD3<Double>
        /// The surface normal, turned to face the arriving light.
        public var normal: SIMD3<Double>
        /// The angle of incidence, from the normal.
        public var incidence: Double
        /// The refracted light's angle from the normal, where there was any.
        public var refraction: Double?
        public var nanometers: Double
        /// The power that arrived.
        public var power: Double
        /// The fraction reflected (Fresnel, or the mirror's reflectance).
        public var reflectance: Double
    }

    public struct Result: Sendable {
        public var segments: [Segment] = []
        public var landings: [Landing] = []
        public var events: [Event] = []
        /// Power a mirror absorbed (its losses, and anything on its back).
        public var absorbed: Double = 0
        /// Power that met nothing within `Room.maxSegment`.
        public var escaped: Double = 0
        /// Power on branches too faint or too deep to follow.
        public var dropped: Double = 0

        public var landed: Double { landings.reduce(0) { $0 + $1.power } }
        /// Everything accounted for: equals the sources' total power.
        public var total: Double { landed + absorbed + escaped + dropped }
    }

    /// Thirteen wavelengths across the visible, 400–700 nm: enough that a
    /// prism's fan reads as a continuous spectrum.
    public static let visibleSpectrum: [Double] = (0...12).map { 400 + 25 * Double($0) }

    // MARK: Tracing

    /// Traces `rays` through `elements` until each branch lands, is
    /// absorbed, meets nothing, or fades below `options.minFraction`.
    public static func trace(_ rays: [Ray], elements: [OpticalElement],
                             room: Room = .open, options: Options = Options()) -> Result {
        var tracer = Tracer(elements: elements, room: room, options: options)
        for ray in rays {
            tracer.stack.append(Work(origin: ray.origin, direction: ray.direction,
                                     nanometers: ray.nanometers, power: ray.power,
                                     floor: ray.power * options.minFraction,
                                     inside: nil, depth: 0))
            tracer.run()
        }
        return tracer.result
    }

    // MARK: Closed forms

    /// A prism's deviation for light meeting its first face at
    /// `incidence`: δ = θ₁ + θ₄ − A, or nil if the light is totally
    /// internally reflected at the second face.
    public static func prismDeviation(apexAngle a: Double, index n: Double,
                                      incidence: Double) -> Double? {
        let inside1 = asin(sin(incidence) / n)
        let inside2 = a - inside1
        let out = n * sin(inside2)
        guard abs(out) <= 1 else { return nil }
        return incidence + asin(out) - a
    }

    /// The least deviation a prism can give, reached when the light
    /// crosses it symmetrically: δ_min = 2 arcsin(n sin(A/2)) − A.
    public static func minimumDeviation(apexAngle a: Double, index n: Double) -> Double {
        2 * asin(n * sin(a / 2)) - a
    }

    /// The index that a measured minimum deviation implies — how a
    /// prism spectrometer measures glass: n = sin((A + δ)/2) / sin(A/2).
    public static func index(apexAngle a: Double, minimumDeviation d: Double) -> Double {
        sin((a + d) / 2) / sin(a / 2)
    }

    /// The thick-lens lensmaker's equation, with both radii as the
    /// positive magnitudes `OpticalElement.Shape.lens` takes (R₁ = +front,
    /// R₂ = −back in the usual sign convention):
    /// 1/f = (n − 1)[1/R₁ − 1/R₂ + (n − 1)d/(n R₁ R₂)].
    public static func focalLength(frontRadius: Double, backRadius: Double,
                                   thickness d: Double, index n: Double) -> Double {
        let r1 = frontRadius, r2 = -backRadius
        let power = (n - 1) * (1 / r1 - 1 / r2 + (n - 1) * d / (n * r1 * r2))
        return 1 / power
    }

    /// Where a thick lens brings parallel light to a focus, measured from
    /// its back vertex: BFD = f(1 − (n − 1)d/(n R₁)).
    public static func backFocalDistance(frontRadius: Double, backRadius: Double,
                                         thickness d: Double, index n: Double) -> Double {
        let f = focalLength(frontRadius: frontRadius, backRadius: backRadius,
                            thickness: d, index: n)
        return f * (1 - (n - 1) * d / (n * frontRadius))
    }

    static let epsilon = 1e-9
}

// MARK: - The trace itself

private struct Work {
    var origin: SIMD3<Double>
    var direction: SIMD3<Double>
    var nanometers: Double
    var power: Double
    /// Below this the branch is not followed (a fraction of its source).
    var floor: Double
    /// The element whose glass the light is in.
    var inside: Int?
    var depth: Int
}

private struct Tracer {
    let elements: [OpticalElement]
    let solids: [Solid]
    let room: LightTracer.Room
    let options: LightTracer.Options
    var stack: [Work] = []
    var result = LightTracer.Result()

    init(elements: [OpticalElement], room: LightTracer.Room, options: LightTracer.Options) {
        self.elements = elements
        self.solids = elements.map(Solid.init)
        self.room = room
        self.options = options
    }

    mutating func run() {
        while var work = stack.popLast() {
            if work.power < work.floor || work.depth > options.maxDepth {
                result.dropped += work.power
                continue
            }
            work.direction = simd_normalize(work.direction)
            if let index = work.inside {
                insideGlass(work, index: index)
            } else {
                inAir(work)
            }
        }
    }

    /// Inside glass the only way on is out through the solid's own surface.
    private mutating func insideGlass(_ work: Work, index: Int) {
        let element = elements[index]
        let local = (element.toLocal(point: work.origin), element.toLocal(direction: work.direction))
        guard let span = solids[index].span(origin: local.0, direction: local.1),
              span.exit.t > LightTracer.epsilon else {
            // A ray inside a convex solid always leaves it; reaching here is
            // numerical, and the light is not invented.
            result.dropped += work.power
            return
        }
        let point = work.origin + span.exit.t * work.direction
        result.segments.append(.init(a: work.origin, b: point, nanometers: work.nanometers,
                                     power: work.power, inside: element.id))
        let n1 = element.glass.index(nanometers: work.nanometers)
        split(work, at: point, outward: element.toWorld(direction: span.exit.normal),
              from: n1, into: 1, elementIndex: index)
    }

    private mutating func inAir(_ work: Work) {
        var nearest = room.maxSegment
        var element: (index: Int, normal: SIMD3<Double>, front: Bool)?
        var landing: (normal: SIMD3<Double>, surface: LightTracer.Landing.Surface)?

        for (index, candidate) in elements.enumerated() {
            let origin = candidate.toLocal(point: work.origin)
            let direction = candidate.toLocal(direction: work.direction)
            if case .mirror(let radius, _) = candidate.shape {
                guard abs(direction.z) > 1e-15 else { continue }
                let t = -origin.z / direction.z
                guard t > LightTracer.epsilon, t < nearest else { continue }
                let p = origin + t * direction
                guard p.x * p.x + p.y * p.y <= radius * radius else { continue }
                nearest = t
                let front = direction.z < 0
                let face = candidate.toWorld(direction: SIMD3(0, 0, front ? 1 : -1))
                element = (index, face, front)
                landing = nil
                continue
            }
            // Glass: entered only from outside, at the start of its span.
            guard let span = solids[index].span(origin: origin, direction: direction),
                  span.entry.t > LightTracer.epsilon, span.entry.t < nearest else { continue }
            nearest = span.entry.t
            element = (index, candidate.toWorld(direction: span.entry.normal), true)
            landing = nil
        }
        for (index, wall) in room.walls.enumerated() {
            guard let t = Self.wallHit(wall, origin: work.origin, direction: work.direction),
                  t < nearest else { continue }
            nearest = t
            element = nil
            let facing = simd_dot(wall.normal, work.direction) < 0 ? wall.normal : -wall.normal
            landing = (facing, .wall(index))
        }
        if let floorY = room.floorY, work.direction.y < -1e-12, work.origin.y > floorY {
            let t = (floorY - work.origin.y) / work.direction.y
            if t > LightTracer.epsilon, t < nearest {
                nearest = t
                element = nil
                landing = (SIMD3(0, 1, 0), .floor)
            }
        }

        let end = work.origin + nearest * work.direction
        result.segments.append(.init(a: work.origin, b: end, nanometers: work.nanometers,
                                     power: work.power, inside: nil))

        if let hit = element {
            let candidate = elements[hit.index]
            if case .mirror(_, let reflectance) = candidate.shape {
                let cosI = min(1, abs(simd_dot(work.direction, hit.normal)))
                let kept = hit.front ? reflectance : 0
                result.events.append(.init(element: candidate.id, kind: .mirror, point: end,
                                           normal: hit.normal, incidence: acos(cosI),
                                           refraction: nil, nanometers: work.nanometers,
                                           power: work.power, reflectance: kept))
                result.absorbed += work.power * (1 - kept)
                guard kept > 0 else { return }
                var next = work
                next.origin = end
                next.direction = Refraction.reflect(direction: work.direction, normal: hit.normal)
                next.power = work.power * kept
                next.depth += 1
                stack.append(next)
            } else {
                let n2 = candidate.glass.index(nanometers: work.nanometers)
                split(work, at: end, outward: hit.normal, from: 1, into: n2,
                      elementIndex: hit.index)
            }
        } else if let landing {
            result.landings.append(.init(point: end, normal: landing.normal,
                                         direction: work.direction,
                                         nanometers: work.nanometers, power: work.power,
                                         surface: landing.surface))
        } else {
            result.escaped += work.power
        }
    }

    /// Splits the light at a glass surface: the Fresnel fraction reflects,
    /// the rest refracts; past the critical angle all of it reflects.
    /// `outward` is the solid's outward normal there.
    private mutating func split(_ work: Work, at point: SIMD3<Double>, outward: SIMD3<Double>,
                                from n1: Double, into n2: Double, elementIndex: Int) {
        let element = elements[elementIndex]
        let entering = work.inside == nil
        // The normal facing the arriving light.
        let facing = simd_dot(outward, work.direction) < 0 ? outward : -outward
        let cosI = min(1, max(0, -simd_dot(work.direction, facing)))
        let fresnel = Fresnel.reflectance(cosIncidence: cosI, n1: n1, n2: n2)
        let refracted = Refraction.refract(direction: work.direction, normal: facing,
                                           n1: n1, n2: n2)
        let reflectance = refracted == nil ? 1 : fresnel.unpolarised
        let kind: LightTracer.Event.Kind = refracted == nil ? .totalInternalReflection
            : (entering ? .enter : .exit)
        result.events.append(.init(
            element: element.id, kind: kind, point: point, normal: facing,
            incidence: acos(cosI),
            refraction: refracted.map { acos(min(1, abs(simd_dot($0, facing)))) },
            nanometers: work.nanometers, power: work.power, reflectance: reflectance))

        // Reflected: back into the medium it came from.
        let reflected = work.power * reflectance
        if refracted == nil || options.followsPartialReflections {
            var next = work
            next.origin = point
            next.direction = Refraction.reflect(direction: work.direction, normal: facing)
            next.power = reflected
            next.depth += 1
            stack.append(next)
        } else {
            result.dropped += reflected
        }
        // Transmitted: across into the other medium.
        if let refracted {
            var next = work
            next.origin = point
            next.direction = refracted
            next.power = work.power - reflected
            next.inside = entering ? elementIndex : nil
            next.depth += 1
            stack.append(next)
        }
    }

    /// Where a ray meets a wall's rectangle (from either face), if it does.
    static func wallHit(_ wall: RoomWalls.Wall, origin: SIMD3<Double>,
                        direction: SIMD3<Double>) -> Double? {
        let denominator = simd_dot(direction, wall.normal)
        guard abs(denominator) > 1e-12 else { return nil }
        let t = simd_dot(wall.center - origin, wall.normal) / denominator
        guard t > LightTracer.epsilon else { return nil }
        let offset = origin + t * direction - wall.center
        guard abs(simd_dot(offset, wall.uAxis)) <= wall.halfU,
              abs(simd_dot(offset, wall.vAxis)) <= wall.halfV else { return nil }
        return t
    }
}

// MARK: - Convex solids

/// A glass element as an intersection of primitives, in its local frame.
private struct Solid {
    enum Bound {
        /// Inside where n·x ≤ offset; n is the outward normal.
        case plane(normal: SIMD3<Double>, offset: Double)
        case ball(center: SIMD3<Double>, radius: Double)
        /// An infinite cylinder about the local z-axis.
        case cylinder(radius: Double)
    }

    struct Crossing {
        var t: Double
        /// The outward normal there, local frame.
        var normal: SIMD3<Double>
    }

    let bounds: [Bound]

    init(_ element: OpticalElement) {
        switch element.shape {
        case .mirror:
            bounds = []
        case .block(let h):
            bounds = [
                .plane(normal: [1, 0, 0], offset: h.x), .plane(normal: [-1, 0, 0], offset: h.x),
                .plane(normal: [0, 1, 0], offset: h.y), .plane(normal: [0, -1, 0], offset: h.y),
                .plane(normal: [0, 0, 1], offset: h.z), .plane(normal: [0, 0, -1], offset: h.z),
            ]
        case .prism(let apex, let side, let length):
            let corners = OpticalElement.prismCorners(apexAngle: apex, side: side)
            let half = apex / 2
            let left = SIMD3(-cos(half), sin(half), 0)
            let right = SIMD3(cos(half), sin(half), 0)
            let apexPoint = SIMD3(corners[0].x, corners[0].y, 0)
            bounds = [
                .plane(normal: left, offset: simd_dot(left, apexPoint)),
                .plane(normal: right, offset: simd_dot(right, apexPoint)),
                .plane(normal: [0, -1, 0], offset: -corners[1].y),
                .plane(normal: [0, 0, 1], offset: length / 2),
                .plane(normal: [0, 0, -1], offset: length / 2),
            ]
        case .lens(let front, let back, let thickness, let diameter):
            var parts: [Bound] = [.cylinder(radius: diameter / 2)]
            // The front face's vertex is at z = −d/2 and its centre of
            // curvature R₁ behind it; likewise the back face.
            if front.isFinite {
                parts.append(.ball(center: [0, 0, -thickness / 2 + front], radius: front))
            } else {
                parts.append(.plane(normal: [0, 0, -1], offset: thickness / 2))
            }
            if back.isFinite {
                parts.append(.ball(center: [0, 0, thickness / 2 - back], radius: back))
            } else {
                parts.append(.plane(normal: [0, 0, 1], offset: thickness / 2))
            }
            bounds = parts
        }
    }

    /// The interval along the ray (local frame, unit direction) that lies
    /// inside the solid, or nil if the line misses it.
    func span(origin o: SIMD3<Double>, direction d: SIMD3<Double>)
        -> (entry: Crossing, exit: Crossing)? {
        guard !bounds.isEmpty else { return nil }
        var entry = Crossing(t: -.infinity, normal: .zero)
        var exit = Crossing(t: .infinity, normal: .zero)
        for bound in bounds {
            switch bound {
            case .plane(let n, let offset):
                let denominator = simd_dot(n, d)
                let distance = offset - simd_dot(n, o)
                if abs(denominator) < 1e-15 {
                    if distance < 0 { return nil }
                    continue
                }
                let t = distance / denominator
                if denominator > 0 {
                    if t < exit.t { exit = Crossing(t: t, normal: n) }
                } else if t > entry.t {
                    entry = Crossing(t: t, normal: n)
                }
            case .ball(let center, let radius):
                let oc = o - center
                let b = simd_dot(oc, d)
                let c = simd_dot(oc, oc) - radius * radius
                let discriminant = b * b - c
                guard discriminant >= 0 else { return nil }
                let root = discriminant.squareRoot()
                let t0 = -b - root, t1 = -b + root
                if t0 > entry.t { entry = Crossing(t: t0, normal: (o + t0 * d - center) / radius) }
                if t1 < exit.t { exit = Crossing(t: t1, normal: (o + t1 * d - center) / radius) }
            case .cylinder(let radius):
                let a = d.x * d.x + d.y * d.y
                let b = o.x * d.x + o.y * d.y
                let c = o.x * o.x + o.y * o.y - radius * radius
                if a < 1e-18 {
                    if c > 0 { return nil }
                    continue
                }
                let discriminant = b * b - a * c
                guard discriminant >= 0 else { return nil }
                let root = discriminant.squareRoot()
                let t0 = (-b - root) / a, t1 = (-b + root) / a
                func radial(_ t: Double) -> SIMD3<Double> {
                    let p = o + t * d
                    return SIMD3(p.x, p.y, 0) / radius
                }
                if t0 > entry.t { entry = Crossing(t: t0, normal: radial(t0)) }
                if t1 < exit.t { exit = Crossing(t: t1, normal: radial(t1)) }
            }
        }
        guard entry.t < exit.t else { return nil }
        return (entry, exit)
    }
}
