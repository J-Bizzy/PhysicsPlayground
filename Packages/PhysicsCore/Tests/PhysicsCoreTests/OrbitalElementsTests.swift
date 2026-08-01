//
//  OrbitalElementsTests.swift
//  PhysicsCoreTests
//
//  The orbit-as-object math, pinned. Three groups, and the third is the
//  one the interaction lives or dies on:
//
//  1. ROUND TRIPS. State → elements → state and back, over a table that
//     includes every degenerate configuration, because a convention that
//     is merely deterministic is enough to make the round trip exact even
//     where the physics is indifferent — and if it isn't exact, some
//     branch is picking a different answer on the way back.
//  2. TIES TO SHIPPED CODE. `onCircularOrbit` and `onEllipticalOrbit`
//     have built every body in Gravity Lab for months. The new math has
//     to agree with them, which is what catches a sign error in the +y-up
//     frame — the failure that would otherwise look perfectly correct in
//     a still frame and build the entire solar system retrograde.
//  3. THE DRAG. In-plane drags must leave the orbital plane BIT-EXACT
//     (`==`, not `≈` — a drag runs at ninety frames a second for as long
//     as a hand is moving, so a per-frame ulp of error is a random walk
//     that visibly tilts the orbit with nothing in the gesture to explain
//     it), the near/far swap must pass through the circular crossing
//     without a jump, and the transport rule must have the holonomy that
//     justifies there being only two beads and not three.
//

import XCTest
import simd
@testable import PhysicsCore

final class OrbitalElementsTests: XCTestCase {

    private let au = CelestialBody.astronomicalUnit
    private let sunMu = NBody.gravitationalConstant * 1.989e30

    /// The orbits every test sweeps. Each one is here because it breaks
    /// something naive: the circular ones have no periapsis, the
    /// equatorial ones have no node, the retrograde one inverts the
    /// measuring axis, and the last two are not ellipses at all.
    private var table: [(name: String, elements: OrbitalElements)] {
        func make(_ a: Double, _ e: Double, _ i: Double,
                  _ raan: Double, _ argP: Double, _ nu: Double) -> OrbitalElements {
            OrbitalElements(
                semiMajorAxis: a, semiLatusRectum: a * (1 - e * e),
                eccentricity: e, inclination: i,
                longitudeOfAscendingNode: raan, argumentOfPeriapsis: argP,
                trueAnomaly: nu, mu: sunMu)
        }
        return [
            ("circular equatorial", make(au, 0, 0, 0, 0, 0.9)),
            ("Earth", make(au, 0.0167, 0, 0, 0, 1.3)),
            ("inclined ellipse", make(2.1 * au, 0.42, 0.6, 1.1, 2.4, -0.7)),
            ("Halley", make(17.834 * au, 0.967, 162 * .pi / 180, 1.9, 0.3, 2.6)),
            ("polar", make(1.4 * au, 0.31, .pi / 2, 0.4, 1.7, 0.2)),
            ("retrograde equatorial", make(au, 0.2, .pi, 0, 1.05, -2.2)),
            ("nearly parabolic", make(30 * au, 0.999, 0.9, 2.2, 0.8, 0.4)),
        ]
    }

    // MARK: 1 — Round trips

    func testStateRoundTripsThroughElements() {
        for entry in table {
            let (position, velocity) = entry.elements.state()
            guard let back = OrbitalElements.from(
                position: position, velocity: velocity, mu: sunMu) else {
                XCTFail("\(entry.name): no elements recovered"); continue
            }
            let (position2, velocity2) = back.state()
            XCTAssertEqual(simd_distance(position, position2) / simd_length(position),
                           0, accuracy: 1e-9, "\(entry.name): position drifted")
            XCTAssertEqual(simd_distance(velocity, velocity2) / simd_length(velocity),
                           0, accuracy: 1e-9, "\(entry.name): velocity drifted")
        }
    }

    func testElementsRoundTripThroughState() {
        for entry in table {
            let original = entry.elements
            let (position, velocity) = original.state()
            guard let back = OrbitalElements.from(
                position: position, velocity: velocity, mu: sunMu) else {
                XCTFail("\(entry.name): no elements recovered"); continue
            }
            XCTAssertEqual(back.eccentricity, original.eccentricity,
                           accuracy: max(original.eccentricity, 1) * 1e-9,
                           "\(entry.name): e")
            XCTAssertEqual(back.semiLatusRectum / original.semiLatusRectum, 1,
                           accuracy: 1e-9, "\(entry.name): p")
            XCTAssertEqual(back.inclination, original.inclination,
                           accuracy: 1e-9, "\(entry.name): i")
            assertAngle(back.trueAnomaly, original.trueAnomaly,
                        "\(entry.name): ν")
            // Ω and ω are only individually meaningful when the orbit has
            // a node and a periapsis to measure them from; where it does
            // not, their SUM is what survives, and the round trip has to
            // preserve that much.
            if back.degeneracy == .none {
                assertAngle(back.longitudeOfAscendingNode,
                            original.longitudeOfAscendingNode, "\(entry.name): Ω")
                assertAngle(back.argumentOfPeriapsis,
                            original.argumentOfPeriapsis, "\(entry.name): ω")
            }
        }
    }

    func testTheHandleRoundTripsThroughState() {
        for entry in table {
            let frame = entry.elements.frame
            let (position, velocity) = frame.state()
            guard let back = ApsisFrame(position: position, velocity: velocity,
                                        mu: sunMu) else {
                XCTFail("\(entry.name): no frame recovered"); continue
            }
            XCTAssertEqual(back.periapsisRadius / frame.periapsisRadius, 1,
                           accuracy: 1e-9, "\(entry.name): r_p")
            XCTAssertEqual(simd_length(back.orbitNormal - frame.orbitNormal), 0,
                           accuracy: 1e-9, "\(entry.name): ĥ")
            if frame.eccentricity > 1e-6 {
                XCTAssertEqual(
                    simd_length(back.periapsisDirection - frame.periapsisDirection),
                    0, accuracy: 1e-8, "\(entry.name): p̂")
            }
        }
    }

    // MARK: 2 — Ties to the code that already builds this app's bodies

    /// The sign test. `onCircularOrbit` is what every planet in Gravity
    /// Lab is built with; if the new math reads its output as retrograde,
    /// everything downstream is quietly mirrored.
    func testPrograderCircularOrbitReadsAsInclinationZero() {
        let sun = CelestialBody.sun
        let earth = CelestialBody.earth.onCircularOrbit(of: sun, distance: au)
        guard let elements = OrbitalElements.from(
            position: earth.position - sun.position,
            velocity: earth.velocity - sun.velocity,
            mu: NBody.standardGravitationalParameter(
                primaryMass: sun.mass, bodyMass: earth.mass)) else {
            return XCTFail("a circular orbit produced no elements")
        }
        XCTAssertEqual(elements.eccentricity, 0, accuracy: 1e-12)
        XCTAssertEqual(elements.inclination, 0, accuracy: 1e-12)
        XCTAssertEqual(elements.degeneracy, .circularEquatorial)
        // h along +ŷ is what "prograde" means in this project's frame.
        let h = simd_cross(earth.position - sun.position,
                           earth.velocity - sun.velocity)
        XCTAssertGreaterThan(h.y, 0, "the app builds its orbits retrograde")
    }

    func testEllipticalBuilderReturnsTheElementsItWasGiven() {
        let sun = CelestialBody.sun
        let a = 17.834 * au, e = 0.967, i = 162 * Double.pi / 180
        let comet = CelestialBody.comet.onEllipticalOrbit(
            of: sun, semiMajorAxis: a, eccentricity: e, inclination: i)
        guard let elements = OrbitalElements.from(
            position: comet.position - sun.position,
            velocity: comet.velocity - sun.velocity,
            mu: NBody.standardGravitationalParameter(
                primaryMass: sun.mass, bodyMass: comet.mass)) else {
            return XCTFail("the comet produced no elements")
        }
        XCTAssertEqual(elements.eccentricity, e, accuracy: 1e-9)
        XCTAssertEqual(elements.semiMajorAxis! / a, 1, accuracy: 1e-9)
        XCTAssertEqual(elements.inclination, i, accuracy: 1e-9)
        // The builder places the body AT perihelion.
        assertAngle(elements.trueAnomaly, 0, "the comet is not at perihelion")
    }

    func testPeriodAndSemiMajorAxisAgreeWithNBody() {
        let a = 2.7 * au, e = 0.3
        let elements = OrbitalElements(
            semiMajorAxis: a, semiLatusRectum: a * (1 - e * e), eccentricity: e,
            inclination: 0.2, longitudeOfAscendingNode: 0.5,
            argumentOfPeriapsis: 1.0, trueAnomaly: 0.75, mu: sunMu)
        let (position, velocity) = elements.state()

        let visViva = NBody.semiMajorAxis(
            distance: simd_length(position), speed: simd_length(velocity),
            centralMass: 1.989e30)
        XCTAssertEqual(visViva! / a, 1, accuracy: 1e-12,
                       "the elements disagree with vis-viva")
        XCTAssertEqual(
            elements.period! / NBody.orbitalPeriod(semiMajorAxis: a,
                                                   centralMass: 1.989e30),
            1, accuracy: 1e-12, "the elements disagree with Kepler III")
    }

    /// The claim the whole orbit ring makes: this IS the path, when
    /// nothing else pulls. Integrate a real two-body system for a full
    /// period and the shape must not have moved.
    func testTheOsculatingOrbitIsThePathInATwoBodySystem() {
        let a = 1.6 * au, e = 0.35
        let mu = NBody.standardGravitationalParameter(
            primaryMass: CelestialBody.sun.mass, bodyMass: CelestialBody.earth.mass)
        let elements = OrbitalElements(
            semiMajorAxis: a, semiLatusRectum: a * (1 - e * e), eccentricity: e,
            inclination: 0.4, longitudeOfAscendingNode: 0.9,
            argumentOfPeriapsis: 2.1, trueAnomaly: 0, mu: mu)
        let (position, velocity) = elements.state()

        var bodies = [
            CelestialBody.sun,
            CelestialBody(name: "P", mass: CelestialBody.earth.mass,
                          radius: 6.4e6, position: position, velocity: velocity),
        ]
        // Keep the barycentre still, so "relative to the Sun" stays honest.
        let total = bodies[0].mass + bodies[1].mass
        bodies[0].velocity = -bodies[1].mass * velocity / total
        bodies[1].velocity = bodies[0].velocity + velocity
        bodies[1].position = bodies[0].position + position

        let period = elements.period!
        let steps = 4000
        let dt = period / Double(steps)
        for _ in 0..<steps { NBody.step(bodies: &bodies, dt: dt) }

        guard let after = OrbitalElements.from(
            position: bodies[1].position - bodies[0].position,
            velocity: bodies[1].velocity - bodies[0].velocity, mu: mu) else {
            return XCTFail("the orbit dissolved")
        }
        XCTAssertEqual(after.semiMajorAxis! / a, 1, accuracy: 1e-6,
                       "a drifted over one orbit")
        XCTAssertEqual(after.eccentricity, e, accuracy: 1e-6,
                       "e drifted over one orbit")
        assertAngle(after.trueAnomaly, 0, "the body did not come back round",
                    accuracy: 1e-3)
    }

    // MARK: Degeneracies — flagged, and still exact

    func testCircularOrbitIsFlaggedAndStillRoundTrips() {
        let elements = OrbitalElements(
            semiMajorAxis: au, semiLatusRectum: au, eccentricity: 0,
            inclination: 0.5, longitudeOfAscendingNode: 1.2,
            argumentOfPeriapsis: 0, trueAnomaly: 0.8, mu: sunMu)
        let (position, velocity) = elements.state()
        let back = OrbitalElements.from(position: position, velocity: velocity,
                                        mu: sunMu)!
        XCTAssertEqual(back.degeneracy, .circular)
        XCTAssertEqual(back.eccentricity, 0, accuracy: 1e-12)
        let (position2, velocity2) = back.state()
        XCTAssertEqual(simd_distance(position, position2) / au, 0, accuracy: 1e-12)
        XCTAssertEqual(simd_distance(velocity, velocity2), 0, accuracy: 1e-6)
    }

    func testEquatorialOrbitIsFlaggedWithNoNode() {
        let elements = OrbitalElements(
            semiMajorAxis: au, semiLatusRectum: au * (1 - 0.09), eccentricity: 0.3,
            inclination: 0, longitudeOfAscendingNode: 0,
            argumentOfPeriapsis: 1.4, trueAnomaly: 0.2, mu: sunMu)
        let (position, velocity) = elements.state()
        let back = OrbitalElements.from(position: position, velocity: velocity,
                                        mu: sunMu)!
        XCTAssertEqual(back.degeneracy, .equatorial)
        XCTAssertEqual(back.longitudeOfAscendingNode, 0)
        assertAngle(back.argumentOfPeriapsis, 1.4, "ω from x̂")
    }

    func testRetrogradeEquatorialMeasuresAboutItsOwnNormal() {
        let elements = OrbitalElements(
            semiMajorAxis: au, semiLatusRectum: au * (1 - 0.04), eccentricity: 0.2,
            inclination: .pi, longitudeOfAscendingNode: 0,
            argumentOfPeriapsis: 0.6, trueAnomaly: -1.1, mu: sunMu)
        let (position, velocity) = elements.state()
        let back = OrbitalElements.from(position: position, velocity: velocity,
                                        mu: sunMu)!
        XCTAssertEqual(back.inclination, .pi, accuracy: 1e-9,
                       "a retrograde orbit must not read as prograde")
        assertAngle(back.argumentOfPeriapsis, 0.6, "ω")
        assertAngle(back.trueAnomaly, -1.1, "ν")
    }

    func testHyperbolicOrbitHasNegativeApoapsisAndNoFarBead() {
        // Escape speed × 1.3 at 1 AU, thrown sideways.
        let speed = NBody.escapeSpeed(centralMass: 1.989e30, distance: au) * 1.3
        let frame = ApsisFrame(position: SIMD3(au, 0, 0),
                               velocity: SIMD3(0, 0, -speed), mu: sunMu)!
        XCTAssertGreaterThan(frame.eccentricity, 1)
        XCTAssertLessThan(frame.apoapsisRadius, 0,
                          "a hyperbola's far apsis is behind the focus")
        XCTAssertFalse(frame.hasApoapsis)
        let elements = frame.elements
        XCTAssertEqual(elements.kind, .hyperbola)
        XCTAssertLessThan(elements.semiMajorAxis!, 0)
        XCTAssertNil(elements.period, "an unbound orbit has no period")
        // It is ALSO equatorial, and the two facts are reported
        // separately on purpose: this one happens to lie in the
        // reference plane, which says nothing about whether it comes
        // back. An enum that conflated them could only report one.
        XCTAssertEqual(elements.degeneracy, .equatorial)
    }

    func testRadialFallHasNoOrbitAtAll() {
        // Straight down: r × v = 0, so there is no plane to describe.
        XCTAssertNil(OrbitalElements.from(position: SIMD3(au, 0, 0),
                                          velocity: SIMD3(-3e4, 0, 0), mu: sunMu))
        XCTAssertNil(ApsisFrame(position: SIMD3(au, 0, 0),
                                velocity: SIMD3(-3e4, 0, 0), mu: sunMu))
    }

    // MARK: 3 — The drag

    private func earthFrame(eccentricity e: Double = 0.4) -> ApsisFrame {
        let a = au
        return OrbitalElements(
            semiMajorAxis: a, semiLatusRectum: a * (1 - e * e), eccentricity: e,
            inclination: 0.3, longitudeOfAscendingNode: 0.7,
            argumentOfPeriapsis: 1.2, trueAnomaly: 0.5, mu: sunMu).frame
    }

    /// A straight pull along the apse line changes one distance and
    /// NOTHING else. Bit-exact, because the transport projection is the
    /// identity when the apse line does not move — an approximate answer
    /// here would let the plane wander during ordinary use.
    func testRadialDragLeavesThePlaneBitExact() {
        let frame = earthFrame()
        let pulled = frame.dragged(
            handOffset: frame.periapsisDirection * (frame.periapsisRadius * 0.6),
            otherRadius: frame.apoapsisRadius,
            bodyDirection: simd_normalize(frame.state().position))
        // Bit-exact, and that is the point: the transport short-circuits
        // when the plane is already perpendicular, so an in-plane drag
        // held for a minute at ninety frames a second cannot creep.
        XCTAssertEqual(pulled.orbitNormal, frame.orbitNormal,
                       "a radial pull moved the orbital plane")
        // The apse line is re-derived from the hand through a divide and
        // a normalise, so it lands within an ulp rather than identical.
        XCTAssertEqual(
            simd_length(pulled.periapsisDirection - frame.periapsisDirection), 0,
            accuracy: 1e-15, "a radial pull moved the apse line")
        XCTAssertEqual(pulled.periapsisRadius / (frame.periapsisRadius * 0.6), 1,
                       accuracy: 1e-12)
        XCTAssertEqual(pulled.apoapsisRadius, frame.apoapsisRadius)
    }

    /// Swinging a bead sideways WITHIN the plane rotates the whole
    /// ellipse and still must not tilt it.
    func testInPlaneSwingLeavesThePlaneBitExact() {
        let frame = earthFrame()
        // A direction in the orbital plane, 90° from periapsis.
        let target = frame.alongTrack * frame.periapsisRadius
        let pulled = frame.dragged(
            handOffset: target, otherRadius: frame.apoapsisRadius,
            bodyDirection: simd_normalize(frame.state().position))
        XCTAssertEqual(pulled.orbitNormal, frame.orbitNormal,
                       "an in-plane swing tilted the orbit")
        XCTAssertEqual(simd_length(pulled.periapsisDirection - frame.alongTrack), 0,
                       accuracy: 1e-12)
    }

    /// Lifting a bead out of the plane tilts the orbit by exactly that
    /// much, and the result is still a plane (ĥ ⊥ p̂ to machine epsilon).
    func testOutOfPlaneDragTiltsTheOrbit() {
        let frame = earthFrame()
        let tilt = 0.35
        let lifted = simd_normalize(
            cos(tilt) * frame.periapsisDirection + sin(tilt) * frame.orbitNormal)
        let pulled = frame.dragged(
            handOffset: lifted * frame.periapsisRadius,
            otherRadius: frame.apoapsisRadius,
            bodyDirection: simd_normalize(frame.state().position))

        XCTAssertEqual(simd_dot(pulled.orbitNormal, pulled.periapsisDirection), 0,
                       accuracy: 1e-15, "the frame is no longer orthogonal")
        let turned = acos(min(max(simd_dot(pulled.orbitNormal, frame.orbitNormal),
                                  -1), 1))
        XCTAssertEqual(turned, tilt, accuracy: 1e-9,
                       "the plane did not follow the apse line")
    }

    /// The swap. Drag the near bead continuously out past the far one:
    /// the labels exchange, and the STATE must not jump — because the
    /// exchange happens exactly where e = 0 and the two ends of the orbit
    /// are physically the same thing.
    func testDraggingNearBeadPastFarBeadDoesNotJump() {
        var frame = earthFrame(eccentricity: 0.4)
        let far = frame.apoapsisRadius
        let direction = frame.periapsisDirection
        var previous = frame.state()
        var crossed = false

        // Start the sweep exactly where the near bead already is, so the
        // first step is a no-op. Starting anywhere else would make step
        // zero a real change to the orbit and the test would be
        // measuring that instead of the crossing.
        let start = frame.periapsisRadius / far
        for step in 0...400 {
            let reach = far * (start + (1.5 - start) * Double(step) / 400)
            let bodyDirection = simd_normalize(frame.state().position)
            frame = frame.dragged(handOffset: direction * reach,
                                  otherRadius: far, bodyDirection: bodyDirection)
            let now = frame.state()
            let jump = simd_distance(previous.position, now.position)
            XCTAssertLessThan(jump / au, 0.02,
                              "the orbit jumped at step \(step)")
            let speedJump = simd_distance(previous.velocity, now.velocity)
            XCTAssertLessThan(speedJump, 800,
                              "the velocity jumped at step \(step)")
            if reach > far { crossed = true }
            previous = now
        }
        XCTAssertTrue(crossed)
        // Past the crossing the held bead IS the far one, so the apse
        // line has flipped to point the other way.
        XCTAssertLessThan(simd_dot(frame.periapsisDirection, direction), 0,
                          "the apse line never flipped")
    }

    /// The holonomy that licenses there being only two beads.
    ///
    /// Transport is parallel transport, so walking the apse line around a
    /// closed loop on the sphere brings the plane back rotated by the
    /// enclosed solid angle. An octant of the sphere encloses exactly
    /// π/2 steradians, so the plane must come back turned by π/2 — which
    /// means the roll no bead can set directly IS reachable, by circling.
    func testTransportHasHolonomyEqualToTheEnclosedSolidAngle() {
        let radius = au
        // Start with the apse line on +x and the plane's normal on +y.
        var frame = ApsisFrame(
            periapsisDirection: SIMD3(1, 0, 0), orbitNormal: SIMD3(0, 1, 0),
            periapsisRadius: radius, apoapsisRadius: radius * 2,
            trueAnomaly: 0, mu: sunMu)
        let startNormal = frame.orbitNormal

        // Walk p̂ around the spherical triangle (+x → +z → +y → +x).
        let corners: [SIMD3<Double>] = [
            SIMD3(1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0), SIMD3(1, 0, 0),
        ]
        for leg in 0..<(corners.count - 1) {
            let from = corners[leg], to = corners[leg + 1]
            for step in 1...200 {
                let t = Double(step) / 200
                let direction = simd_normalize(from * (1 - t) + to * t)
                frame = frame.dragged(handOffset: direction * radius,
                                      otherRadius: radius * 2,
                                      bodyDirection: direction)
            }
        }

        XCTAssertEqual(simd_length(frame.periapsisDirection - SIMD3(1, 0, 0)), 0,
                       accuracy: 1e-9, "the apse line did not return")
        let turned = acos(min(max(simd_dot(frame.orbitNormal, startNormal), -1), 1))
        XCTAssertEqual(turned, .pi / 2, accuracy: 1e-3,
                       "transport has no holonomy — the roll would be unreachable")
    }

    /// Degenerate hands are no-ops. A hand at the focus has no direction,
    /// and a hand on the orbit's pole describes every plane equally.
    func testDegenerateDragsLeaveTheOrbitAlone() {
        let frame = earthFrame()
        let body = simd_normalize(frame.state().position)

        XCTAssertEqual(frame.dragged(handOffset: .zero,
                                     otherRadius: frame.apoapsisRadius,
                                     bodyDirection: body), frame,
                       "a hand at the focus changed the orbit")
        XCTAssertEqual(frame.dragged(handOffset: frame.orbitNormal * frame.periapsisRadius,
                                     otherRadius: frame.apoapsisRadius,
                                     bodyDirection: body), frame,
                       "a hand on the pole snapped the plane instead of holding it")
    }

    /// Dragging an unbound orbit's one bead keeps its shape — there is no
    /// second bead to pin anything, so eccentricity is what holds.
    func testDraggingAnUnboundOrbitPreservesItsShape() {
        let speed = NBody.escapeSpeed(centralMass: 1.989e30, distance: au) * 1.3
        let frame = ApsisFrame(position: SIMD3(au, 0, 0),
                               velocity: SIMD3(0, 0, -speed), mu: sunMu)!
        let pulled = frame.dragged(
            handOffset: frame.periapsisDirection * (frame.periapsisRadius * 1.5),
            otherRadius: frame.apoapsisRadius,
            bodyDirection: simd_normalize(frame.state().position))
        XCTAssertEqual(pulled.eccentricity, frame.eccentricity, accuracy: 1e-9)
        XCTAssertEqual(pulled.periapsisRadius / (frame.periapsisRadius * 1.5), 1,
                       accuracy: 1e-12)
        XCTAssertFalse(pulled.hasApoapsis)
    }

    // MARK: Drawing

    func testSampledPointsLieOnTheConicAndInItsPlane() {
        for entry in table {
            let frame = entry.elements.frame
            guard frame.isBound else { continue }
            let points = frame.sampled(count: 128)
            let p = frame.semiLatusRectum, e = frame.eccentricity
            for point in points {
                XCTAssertEqual(simd_dot(point, frame.orbitNormal) / au, 0,
                               accuracy: 1e-9, "\(entry.name): point off-plane")
                let nu = OrbitalElements.signedAngle(
                    from: frame.periapsisDirection,
                    to: simd_normalize(point), about: frame.orbitNormal)
                XCTAssertEqual(simd_length(point) / (p / (1 + e * cos(nu))), 1,
                               accuracy: 1e-9, "\(entry.name): point off-conic")
            }
        }
    }

    func testASampledEllipseStartsAtPeriapsisAndCloses() {
        let frame = earthFrame(eccentricity: 0.6)
        let points = frame.sampled(count: 64)
        XCTAssertEqual(simd_length(points.first!) / frame.periapsisRadius, 1,
                       accuracy: 1e-9, "the ring does not start at periapsis")
        XCTAssertEqual(simd_distance(points.first!, points.last!) / au, 0,
                       accuracy: 1e-9, "the ring does not close")
        // The far side really is the far side.
        let mid = points[points.count / 2]
        XCTAssertEqual(simd_length(mid) / frame.apoapsisRadius, 1, accuracy: 1e-6)
    }

    /// Eccentric-anomaly sampling exists to space points evenly along the
    /// arc. On a very eccentric orbit, true-anomaly sampling would crowd
    /// the slow far end and facet the fast nose; this pins that it does
    /// not.
    func testSamplingIsEvenlySpacedOnAnEccentricOrbit() {
        let frame = earthFrame(eccentricity: 0.9)
        let points = frame.sampled(count: 256)
        let gaps = (1..<points.count).map {
            simd_distance(points[$0], points[$0 - 1])
        }
        let longest = gaps.max()!, shortest = gaps.min()!
        XCTAssertLessThan(longest / shortest, 3.0,
                          "the ring is faceted at one end and wasted at the other")
    }

    // MARK: Helpers

    private func assertAngle(_ actual: Double, _ expected: Double,
                             _ message: String, accuracy: Double = 1e-9,
                             file: StaticString = #filePath, line: UInt = #line) {
        var difference = (actual - expected).truncatingRemainder(dividingBy: 2 * .pi)
        if difference > .pi { difference -= 2 * .pi }
        if difference < -.pi { difference += 2 * .pi }
        XCTAssertEqual(difference, 0, accuracy: accuracy, message,
                       file: file, line: line)
    }
}
