//
//  LightTracerTests.swift
//  PhysicsCoreTests
//
//  The room-scale tracer against the closed forms of geometric optics:
//  the glass catalogue's own indices, Fresnel at normal incidence and at
//  Brewster's angle, Snell at a rotated surface, a slab's parallel
//  shift, total internal reflection switching on exactly at the critical
//  angle, a prism's minimum deviation recovering the glass's index (the
//  way a spectrometer measures it), a thick lens's back focal distance
//  and its spherical aberration, and power that is never invented or
//  lost. None of it is fitted: each number is the textbook's.
//

import XCTest
import simd
@testable import PhysicsCore

final class LightTracerTests: XCTestCase {

    private let identity = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)

    // MARK: Glass

    /// Schott's catalogue values for N-BK7 and SF11 at the Fraunhofer
    /// lines, and their Abbe numbers.
    func testSellmeierMatchesTheCatalogue() {
        XCTAssertEqual(Glass.nbk7.index(nanometers: Glass.dLine), 1.5168, accuracy: 1e-4)
        XCTAssertEqual(Glass.nbk7.index(nanometers: Glass.fLine), 1.5224, accuracy: 1e-4)
        XCTAssertEqual(Glass.nbk7.index(nanometers: Glass.cLine), 1.5143, accuracy: 1e-4)
        XCTAssertEqual(Glass.nbk7.abbeNumber, 64.17, accuracy: 0.2)
        XCTAssertEqual(Glass.sf11.index(nanometers: Glass.dLine), 1.78472, accuracy: 1e-4)
        XCTAssertEqual(Glass.sf11.abbeNumber, 25.68, accuracy: 0.2)
    }

    /// Normal dispersion: across the visible, the index only falls as the
    /// wavelength grows.
    func testBlueSeesAHigherIndexThanRed() {
        for glass in [Glass.nbk7, .sf11] {
            var previous = Double.infinity
            for nm in stride(from: 400.0, through: 700, by: 10) {
                let n = glass.index(nanometers: nm)
                XCTAssertLessThan(n, previous)
                previous = n
            }
        }
    }

    // MARK: Fresnel

    func testFresnelAtNormalIncidenceIsTheTextbookFourPercent() {
        let n = 1.5
        let r = Fresnel.reflectance(cosIncidence: 1, n1: 1, n2: n)
        let expected = pow((n - 1) / (n + 1), 2)
        XCTAssertEqual(r.s, expected, accuracy: 1e-15)
        XCTAssertEqual(r.p, expected, accuracy: 1e-15)
        XCTAssertEqual(r.unpolarised, 0.04, accuracy: 1e-15)
    }

    /// At Brewster's angle the p-polarised reflection vanishes.
    func testBrewstersAngleTransmitsAllPPolarisedLight() {
        let theta = Fresnel.brewsterAngle(n1: 1, n2: 1.5168)
        let r = Fresnel.reflectance(cosIncidence: cos(theta), n1: 1, n2: 1.5168)
        XCTAssertEqual(r.p, 0, accuracy: 1e-15)
        XCTAssertGreaterThan(r.s, 0.05)
    }

    /// Stokes reciprocity: a surface reflects the same fraction whichever
    /// way the light crosses it, at the matching pair of angles.
    func testFresnelIsReciprocal() {
        let n1 = 1.0, n2 = 1.5168
        for degrees in stride(from: 0.0, through: 85, by: 5) {
            let thetaI = degrees * .pi / 180
            let thetaT = asin(n1 / n2 * sin(thetaI))
            let forward = Fresnel.reflectance(cosIncidence: cos(thetaI), n1: n1, n2: n2)
            let backward = Fresnel.reflectance(cosIncidence: cos(thetaT), n1: n2, n2: n1)
            XCTAssertEqual(forward.unpolarised, backward.unpolarised, accuracy: 1e-12)
        }
    }

    func testPastTheCriticalAngleEverythingReflects() {
        let critical = asin(1 / 1.5)
        let r = Fresnel.reflectance(cosIncidence: cos(critical + 1e-6), n1: 1.5, n2: 1)
        XCTAssertEqual(r.unpolarised, 1)
        let short = Fresnel.reflectance(cosIncidence: cos(critical - 1e-3), n1: 1.5, n2: 1)
        XCTAssertLessThan(short.unpolarised, 1)
    }

    // MARK: Refraction at a posed surface

    /// A ray through a block turned to an arbitrary pose: Snell holds at
    /// the entry to machine precision, the refracted ray stays in the
    /// plane of incidence, and the light leaves parallel to how it came,
    /// shifted sideways by exactly t·sin(θ₁ − θ₂)/cos θ₂.
    func testABlockAtAnyPoseObeysSnellAndShiftsTheBeamExactly() throws {
        let pose = simd_quatd(angle: 0.7, axis: simd_normalize(SIMD3(0.3, 1, -0.4)))
        let thickness = 0.1
        let block = OpticalElement(position: SIMD3(0.2, 1.3, -0.8), orientation: pose,
                                   shape: .block(halfExtents: SIMD3(0.05, 0.05, 0.05)))
        // Aim at the centre of the block's −x face at 35° from its normal.
        let normal = pose.act(SIMD3<Double>(-1, 0, 0))
        let tangent = pose.act(SIMD3<Double>(0, 1, 0))
        let theta1 = 35 * Double.pi / 180
        let direction = simd_normalize(-cos(theta1) * normal + sin(theta1) * tangent)
        let face = block.toWorld(point: SIMD3(-0.05, 0, 0))
        let ray = LightTracer.Ray(origin: face - 0.4 * direction, direction: direction,
                                  nanometers: 550)
        let result = LightTracer.trace([ray], elements: [block])

        let enter = try XCTUnwrap(result.events.first { $0.kind == .enter })
        let n = Glass.nbk7.index(nanometers: 550)
        XCTAssertEqual(enter.incidence, theta1, accuracy: 1e-12)
        let theta2 = try XCTUnwrap(enter.refraction)
        XCTAssertEqual(sin(enter.incidence), n * sin(theta2), accuracy: 1e-12)

        let inside = try XCTUnwrap(result.segments.first { $0.inside == block.id })
        let coplanar = simd_dot(simd_cross(direction, enter.normal), inside.direction)
        XCTAssertEqual(coplanar, 0, accuracy: 1e-12)

        // The strongest light leaving the block.
        let out = try XCTUnwrap(result.segments.dropFirst()
            .filter { $0.inside == nil }.max { $0.power < $1.power })
        XCTAssertEqual(simd_distance(out.direction, direction), 0, accuracy: 1e-12)
        let offset = out.a - ray.origin
        let lateral = simd_length(offset - simd_dot(offset, direction) * direction)
        XCTAssertEqual(lateral, thickness * sin(theta1 - theta2) / cos(theta2), accuracy: 1e-12)
    }

    // MARK: Total internal reflection

    /// A right-angle prism turns light 90° by reflecting it off its
    /// hypotenuse at 45° — but only in glass whose critical angle is
    /// below 45°, n > √2. Just under √2 some light gets out; just over,
    /// none does.
    func testTotalInternalReflectionSwitchesOnAtTheCriticalAngle() throws {
        func trace(index: Double) -> LightTracer.Result {
            let prism = OpticalElement(position: .zero,
                                       shape: .prism(apexAngle: .pi / 2, side: 0.1, length: 0.1),
                                       glass: .constant(index))
            let corners = OpticalElement.prismCorners(apexAngle: .pi / 2, side: 0.1)
            let middle = (corners[0] + corners[1]) / 2
            let inward = SIMD3(cos(Double.pi / 4), -sin(Double.pi / 4), 0)
            let start = SIMD3(middle.x, middle.y, 0) - 0.3 * inward
            return LightTracer.trace([.init(origin: start, direction: inward, nanometers: 550)],
                                     elements: [prism])
        }
        let below = trace(index: 1.4142)
        let base = try XCTUnwrap(below.events.first { abs($0.normal.y - 1) < 1e-9 })
        XCTAssertEqual(base.kind, .exit)
        XCTAssertEqual(base.incidence, .pi / 4, accuracy: 1e-12)

        let above = trace(index: 1.4143)
        let reflected = try XCTUnwrap(above.events.first { abs($0.normal.y - 1) < 1e-9 })
        XCTAssertEqual(reflected.kind, .totalInternalReflection)
        XCTAssertEqual(reflected.reflectance, 1)
        // And the light comes out of the other leg turned through 90°.
        let out = try XCTUnwrap(above.segments.dropFirst()
            .filter { $0.inside == nil }.max { $0.power < $1.power })
        XCTAssertEqual(simd_dot(out.direction, SIMD3(cos(Double.pi / 4), sin(Double.pi / 4), 0)),
                       1, accuracy: 1e-12)
    }

    // MARK: The prism

    /// The deviation through a 60° prism, from the trace, against the
    /// closed form θ₁ + θ₄ − A at a handful of incidences.
    private func traceDeviation(glass: Glass, nanometers: Double, incidence: Double,
                                apex: Double = .pi / 3) -> Double {
        let prism = OpticalElement(position: SIMD3(0, 1.2, -1),
                                   shape: .prism(apexAngle: apex, side: 0.1, length: 0.08),
                                   glass: glass)
        let corners = OpticalElement.prismCorners(apexAngle: apex, side: 0.1)
        let middle = (corners[0] + corners[1]) / 2
        let angle = -apex / 2 + incidence
        let direction = SIMD3(cos(angle), sin(angle), 0)
        let face = prism.toWorld(point: SIMD3(middle.x, middle.y, 0))
        let result = LightTracer.trace(
            [.init(origin: face - 0.3 * direction, direction: direction, nanometers: nanometers)],
            elements: [prism])
        guard let out = result.segments.dropFirst()
            .filter({ $0.inside == nil }).max(by: { $0.power < $1.power }) else { return .nan }
        return acos(min(1, simd_dot(out.direction, direction)))
    }

    func testThePrismDeviatesLightAsTheClosedFormSays() throws {
        let n = Glass.nbk7.index(nanometers: 550)
        for degrees in [42.0, 50, 60, 70] {
            let incidence = degrees * .pi / 180
            let expected = try XCTUnwrap(LightTracer.prismDeviation(apexAngle: .pi / 3, index: n,
                                                                    incidence: incidence))
            XCTAssertEqual(traceDeviation(glass: .nbk7, nanometers: 550, incidence: incidence),
                           expected, accuracy: 1e-12)
        }
    }

    /// Turn the prism until the deviation is least, and the index follows
    /// from n = sin((A + δ_min)/2)/sin(A/2) — how a spectrometer measures
    /// glass. It recovers Sellmeier's index at the F, d and C lines.
    func testMinimumDeviationRecoversTheGlasssIndex() {
        for nm in [Glass.fLine, Glass.dLine, Glass.cLine] {
            var low = 30 * Double.pi / 180, high = 80 * Double.pi / 180
            let golden = (5.0.squareRoot() - 1) / 2
            for _ in 0..<120 {
                let a = high - golden * (high - low), b = low + golden * (high - low)
                if traceDeviation(glass: .nbk7, nanometers: nm, incidence: a)
                    < traceDeviation(glass: .nbk7, nanometers: nm, incidence: b) {
                    high = b
                } else {
                    low = a
                }
            }
            let deviation = traceDeviation(glass: .nbk7, nanometers: nm, incidence: (low + high) / 2)
            let measured = LightTracer.index(apexAngle: .pi / 3, minimumDeviation: deviation)
            XCTAssertEqual(measured, Glass.nbk7.index(nanometers: nm), accuracy: 1e-7)
        }
    }

    /// Dispersion: violet is bent further than red, and flint fans the
    /// spectrum several times wider than crown.
    func testBlueBendsMoreThanRedAndFlintSpreadsWider() {
        // Steep enough that violet still gets out of the flint prism.
        let incidence = 65 * Double.pi / 180
        let crown = (traceDeviation(glass: .nbk7, nanometers: 400, incidence: incidence),
                     traceDeviation(glass: .nbk7, nanometers: 700, incidence: incidence))
        let flint = (traceDeviation(glass: .sf11, nanometers: 400, incidence: incidence),
                     traceDeviation(glass: .sf11, nanometers: 700, incidence: incidence))
        XCTAssertGreaterThan(crown.0, crown.1)
        XCTAssertGreaterThan(flint.0, flint.1)
        XCTAssertGreaterThan((flint.0 - flint.1) / (crown.0 - crown.1), 2.5)
    }

    // MARK: The lens

    /// Where the light parallel to a thick lens's axis at height `h`
    /// crosses the axis, measured from the back vertex.
    private func crossing(height h: Double) -> Double? {
        let thickness = 0.01
        let lens = OpticalElement(position: .zero,
                                  shape: .lens(frontRadius: 0.1, backRadius: 0.1,
                                               thickness: thickness, diameter: 0.06))
        let ray = LightTracer.Ray(origin: SIMD3(h, 0, -0.5), direction: SIMD3(0, 0, 1),
                                  nanometers: Glass.dLine)
        let result = LightTracer.trace([ray], elements: [lens])
        guard let out = result.segments.dropFirst()
            .filter({ $0.inside == nil }).max(by: { $0.power < $1.power }) else { return nil }
        let d = out.direction
        guard abs(d.x) > 1e-15 else { return nil }
        let z = out.a.z + (-out.a.x / d.x) * d.z
        return z - thickness / 2
    }

    /// A paraxial ray focuses at the thick-lens back focal distance.
    func testAParaxialRayFocusesAtTheBackFocalDistance() throws {
        let n = Glass.nbk7.index(nanometers: Glass.dLine)
        let bfd = LightTracer.backFocalDistance(frontRadius: 0.1, backRadius: 0.1,
                                                thickness: 0.01, index: n)
        let traced = try XCTUnwrap(crossing(height: 1e-5))
        XCTAssertEqual(traced / bfd, 1, accuracy: 1e-6)
        // About 10 cm, as the thin-lens rule f ≈ R/2(n − 1) says for R = 10 cm
        // in BK7, less a little for the glass's thickness.
        XCTAssertEqual(bfd, 0.0951, accuracy: 0.0005)
    }

    /// Spherical aberration, which a ray-traced lens has and an ideal one
    /// does not: the rim of the lens focuses short, by an amount that grows
    /// as the square of the height for small heights.
    func testTheRimOfASphericalLensFocusesShort() throws {
        let paraxial = try XCTUnwrap(crossing(height: 1e-5))
        let rim = try XCTUnwrap(crossing(height: 0.025))
        XCTAssertLessThan(rim, paraxial - 0.001)
        let small = try XCTUnwrap(crossing(height: 0.002))
        let smaller = try XCTUnwrap(crossing(height: 0.001))
        let ratio = ((paraxial - small) / (0.002 * 0.002)) / ((paraxial - smaller) / (0.001 * 0.001))
        XCTAssertEqual(ratio, 1, accuracy: 0.02)
    }

    // MARK: Mirrors and the room

    func testAMirrorReflectsAtTheAngleItWasStruckAndItsBackAbsorbs() throws {
        let mirror = OpticalElement(position: SIMD3(0, 1, -1),
                                    orientation: simd_quatd(angle: 0.4, axis: SIMD3(0, 1, 0)),
                                    shape: .mirror(radius: 0.05, reflectance: 0.96))
        let face = mirror.toWorld(direction: SIMD3(0, 0, 1))
        let direction = simd_normalize(SIMD3(0.3, -0.1, -1))
        let front = LightTracer.trace(
            [.init(origin: mirror.position - 0.5 * direction, direction: direction, nanometers: 532)],
            elements: [mirror])
        let event = try XCTUnwrap(front.events.first)
        XCTAssertEqual(event.kind, .mirror)
        let out = front.segments[1].direction
        XCTAssertEqual(acos(simd_dot(out, face)), event.incidence, accuracy: 1e-12)
        XCTAssertEqual(front.segments[1].power, 0.96, accuracy: 1e-15)
        XCTAssertEqual(front.absorbed, 0.04, accuracy: 1e-15)

        // From behind, the backing takes all of it: nothing is reflected
        // and nothing passes through.
        let behind = LightTracer.trace(
            [.init(origin: mirror.position - 0.5 * face, direction: face, nanometers: 532)],
            elements: [mirror])
        XCTAssertEqual(behind.segments.count, 1)
        XCTAssertEqual(behind.absorbed, 1, accuracy: 1e-15)
        XCTAssertEqual(behind.events.first?.reflectance, 0)
    }

    private let farWall = RoomWalls.Wall(center: SIMD3(1, 1, 3), normal: SIMD3(0, 0, -1),
                                         uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 1, 0),
                                         halfU: 2, halfV: 2)

    func testLightLandsOnAWallOnlyWithinItsRectangle() throws {
        let room = LightTracer.Room(walls: [farWall], floorY: 0)
        let hit = LightTracer.trace([.init(origin: SIMD3(1.5, 1.2, 0),
                                           direction: SIMD3(0, 0, 1), nanometers: 650)],
                                    elements: [], room: room)
        let landing = try XCTUnwrap(hit.landings.first)
        XCTAssertEqual(landing.surface, .wall(0))
        XCTAssertEqual(landing.point.z, 3, accuracy: 1e-12)
        XCTAssertEqual(simd_dot(landing.normal, SIMD3(0, 0, -1)), 1, accuracy: 1e-12)

        let past = LightTracer.trace([.init(origin: SIMD3(3.5, 1.2, 0),
                                            direction: SIMD3(0, 0, 1), nanometers: 650)],
                                     elements: [], room: LightTracer.Room(walls: [farWall]))
        XCTAssertTrue(past.landings.isEmpty)
        XCTAssertEqual(past.escaped, 1, accuracy: 1e-15)

        let down = LightTracer.trace([.init(origin: SIMD3(0, 1.5, 0),
                                            direction: SIMD3(0.2, -1, 0.1), nanometers: 650)],
                                     elements: [], room: room)
        XCTAssertEqual(down.landings.first?.surface, .floor)
        XCTAssertEqual(down.landings.first?.point.y ?? -1, 0, accuracy: 1e-12)
    }

    /// A stretch that meets nothing says so, and ends where the tracer
    /// stopped following it — so a drawing can fade it out rather than
    /// show a cut. A stretch that arrives somewhere does not.
    func testLightThatMeetsNothingIsMarkedAsEscaping() throws {
        let room = LightTracer.Room(walls: [farWall], floorY: 0, maxSegment: 6)
        let past = LightTracer.trace([.init(origin: SIMD3(3.5, 1.2, 0),
                                            direction: SIMD3(0, 0, 1), nanometers: 650)],
                                     elements: [], room: room)
        let escaping = try XCTUnwrap(past.segments.first)
        XCTAssertTrue(escaping.escapes)
        XCTAssertEqual(simd_distance(escaping.a, escaping.b), 6, accuracy: 1e-12)

        let hit = LightTracer.trace([.init(origin: SIMD3(1.5, 1.2, 0),
                                           direction: SIMD3(0, 0, 1), nanometers: 650)],
                                    elements: [], room: room)
        XCTAssertFalse(try XCTUnwrap(hit.segments.first).escapes, "a stretch that landed escaped")
    }

    // MARK: The whole scene

    /// A beam folded by a mirror through a turned block and a prism onto a
    /// wall, in every colour.
    private func scene(transform q: simd_quatd = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1),
                       shift c: SIMD3<Double> = .zero)
        -> (rays: [LightTracer.Ray], elements: [OpticalElement], room: LightTracer.Room) {
        func move(_ p: SIMD3<Double>) -> SIMD3<Double> { q.act(p) + c }
        let mirrorNormal = simd_normalize(SIMD3<Double>(-1, 0, 1))
        let elements = [
            OpticalElement(position: move(SIMD3(1, 1, 0)),
                           orientation: q * simd_quatd(from: SIMD3(0, 0, 1), to: mirrorNormal),
                           shape: .mirror(radius: 0.06, reflectance: 0.95)),
            OpticalElement(position: move(SIMD3(1, 1, 0.8)),
                           orientation: q * simd_quatd(angle: 0.35, axis: SIMD3(0, 1, 0)),
                           shape: .block(halfExtents: SIMD3(0.1, 0.08, 0.06))),
            OpticalElement(position: move(SIMD3(1, 1.02, 1.6)),
                           orientation: q * simd_quatd(angle: .pi / 2 + 0.2, axis: SIMD3(0, 1, 0)),
                           shape: .prism(apexAngle: .pi / 3, side: 0.1, length: 0.1)),
        ]
        let rays = LightTracer.visibleSpectrum.map {
            LightTracer.Ray(origin: move(SIMD3(0, 1, 0)), direction: q.act(SIMD3(1, 0, 0)),
                            nanometers: $0, power: 1.0 / 13)
        }
        var wall = farWall
        wall.center = move(wall.center)
        wall.normal = q.act(wall.normal)
        wall.uAxis = q.act(wall.uAxis)
        wall.vAxis = q.act(wall.vAxis)
        return (rays, elements, LightTracer.Room(walls: [wall], maxSegment: 20))
    }

    /// The trace does not care where the room is or which way it faces:
    /// move and turn everything together and every landing moves with it.
    func testTheTraceIsTheSameInAnyFrame() {
        let q = simd_quatd(angle: 1.1, axis: simd_normalize(SIMD3(0.2, -1, 0.5)))
        let c = SIMD3<Double>(-0.7, 0.3, 2.2)
        let plain = scene()
        let moved = scene(transform: q, shift: c)
        let a = LightTracer.trace(plain.rays, elements: plain.elements, room: plain.room)
        let b = LightTracer.trace(moved.rays, elements: moved.elements, room: moved.room)
        XCTAssertFalse(a.landings.isEmpty)
        XCTAssertEqual(a.landings.count, b.landings.count)
        for (x, y) in zip(a.landings, b.landings) {
            XCTAssertEqual(simd_distance(q.act(x.point) + c, y.point), 0, accuracy: 1e-9)
            XCTAssertEqual(x.power, y.power, accuracy: 1e-12)
        }
    }

    /// Light is never invented or lost: what lands, what mirrors absorb,
    /// what meets nothing and what was too faint to follow add up to what
    /// was emitted — with the weak reflections followed or not.
    func testPowerIsAccountedFor() {
        let built = scene()
        for follows in [true, false] {
            let result = LightTracer.trace(built.rays, elements: built.elements, room: built.room,
                                           options: .init(followsPartialReflections: follows))
            XCTAssertEqual(result.total, 1, accuracy: 1e-12)
            XCTAssertGreaterThan(result.landed, 0.5, "the beam should mostly reach the wall")
        }
    }
}
