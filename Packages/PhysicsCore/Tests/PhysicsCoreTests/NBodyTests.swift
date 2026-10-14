//
//  NBodyTests.swift
//  The gravity engine pinned to classical results: stable orbits, energy conservation, Kepler III,
//  and the integrator's own errors — apsidal drift, reversibility, a frozen body, the softening law.
//

import XCTest
import simd
@testable import PhysicsCore

final class NBodyTests: XCTestCase {

    private let day = 86_400.0

    private func sunEarth() -> [CelestialBody] {
        [
            CelestialBody.sun,
            CelestialBody.earth.onCircularOrbit(
                of: .sun, distance: CelestialBody.astronomicalUnit),
        ]
    }

    /// Earth's circular-orbit speed ≈ 29.8 km/s from G, M☉, and 1 AU alone.
    func testCircularOrbitSpeedMatchesEarth() {
        let speed = NBody.circularOrbitSpeed(
            centralMass: CelestialBody.sun.mass,
            distance: CelestialBody.astronomicalUnit)
        XCTAssertEqual(speed, 29_780, accuracy: 100)
    }

    /// Sun–Earth distance drifts under 0.1% over 2 years of 6-hour steps.
    func testCircularOrbitRadiusIsStable() {
        var bodies = sunEarth()
        let dt = 6 * 3600.0
        let au = CelestialBody.astronomicalUnit
        for _ in 0..<Int(2 * 365 * day / dt) {
            NBody.step(bodies: &bodies, dt: dt)
            let r = simd_distance(bodies[0].position, bodies[1].position)
            XCTAssertEqual(r / au, 1.0, accuracy: 1e-3)
        }
    }

    /// The symplectic property that justifies Verlet: tiny energy drift over 5 years.
    func testEnergyIsConservedOverManyOrbits() {
        var bodies = sunEarth()
        let initial = NBody.totalEnergy(bodies: bodies)
        let dt = 6 * 3600.0
        for _ in 0..<Int(5 * 365 * day / dt) {
            NBody.step(bodies: &bodies, dt: dt)
        }
        let drift = abs((NBody.totalEnergy(bodies: bodies) - initial) / initial)
        XCTAssertLessThan(drift, 1e-6, "energy drift over 5 years: \(drift)")
    }

    /// Kepler III emerges: one timed simulated orbit matches T = 2π√(a³/GM) ≈ 365.25 d.
    func testSimulatedPeriodMatchesKeplersThirdLaw() {
        var bodies = sunEarth()
        let dt = 3600.0
        var time = 0.0
        var crossings = 0
        var previousZ = bodies[1].position.z - bodies[0].position.z
        // Crossing 1 is a start artifact; the third z sign change marks one full orbit.
        while crossings < 3, time < 500 * day {
            NBody.step(bodies: &bodies, dt: dt)
            time += dt
            let z = bodies[1].position.z - bodies[0].position.z
            if z.sign != previousZ.sign { crossings += 1 }
            previousZ = z
        }
        let predicted = NBody.orbitalPeriod(
            semiMajorAxis: CelestialBody.astronomicalUnit,
            centralMass: CelestialBody.sun.mass + CelestialBody.earth.mass)
        XCTAssertEqual(time, predicted, accuracy: predicted * 0.01)
        XCTAssertEqual(predicted / day, 365.25, accuracy: 1.0)
    }

    /// Escape = √2 × circular speed; energy is negative just below, positive just above.
    func testEscapeSpeedBoundary() {
        let au = CelestialBody.astronomicalUnit
        let escape = NBody.escapeSpeed(centralMass: CelestialBody.sun.mass, distance: au)
        XCTAssertEqual(escape,
                       NBody.circularOrbitSpeed(centralMass: CelestialBody.sun.mass, distance: au) * 2.0.squareRoot(),
                       accuracy: 1e-6)

        func totalEnergy(speed: Double) -> Double {
            var earth = CelestialBody.earth
            earth.position = SIMD3(au, 0, 0)
            earth.velocity = SIMD3(0, 0, -speed)
            return NBody.totalEnergy(bodies: [.sun, earth])
        }
        XCTAssertLessThan(totalEnergy(speed: escape * 0.99), 0, "below escape → bound")
        XCTAssertGreaterThan(totalEnergy(speed: escape * 1.01), 0, "above escape → unbound")
    }

    /// Vis-viva round trip: recovered semi-major axis matches the one built from.
    func testVisVivaRecoversSemiMajorAxis() {
        let au = CelestialBody.astronomicalUnit
        let mu = NBody.gravitationalConstant * CelestialBody.sun.mass
        let a = 1.3 * au
        let r = 0.9 * au
        let speed = (mu * (2 / r - 1 / a)).squareRoot()   // vis-viva forward
        let recovered = NBody.semiMajorAxis(distance: r, speed: speed,
                                            centralMass: CelestialBody.sun.mass)
        XCTAssertEqual(try XCTUnwrap(recovered), a, accuracy: a * 1e-9)

        let unbound = NBody.semiMajorAxis(
            distance: r,
            speed: NBody.escapeSpeed(centralMass: CelestialBody.sun.mass, distance: r) * 1.01,
            centralMass: CelestialBody.sun.mass)
        XCTAssertNil(unbound, "unbound orbits have no semi-major axis")
    }

    func testMergeConservesMassAndMomentum() {
        var a = CelestialBody.earth
        a.position = SIMD3(1e11, 0, 0)
        a.velocity = SIMD3(0, 0, -30_000)
        var b = CelestialBody.mars
        b.position = SIMD3(1.001e11, 0, 0)
        b.velocity = SIMD3(0, 0, 24_000)

        let merged = NBody.merged(a, b)
        XCTAssertEqual(merged.mass, a.mass + b.mass)
        let momentum = a.mass * a.velocity + b.mass * b.velocity
        XCTAssertEqual(merged.velocity.z, momentum.z / merged.mass, accuracy: 1e-9)
        XCTAssertEqual(merged.name, "Earth", "the heavier body keeps its name")
        XCTAssertGreaterThan(merged.radius, a.radius)
        XCTAssertLessThan(merged.radius, a.radius + b.radius,
                          "volume-additive, not radius-additive")
    }

    /// The predicted path ends where actually propagating the system lands.
    func testPredictedPathMatchesActualEvolution() {
        let bodies = sunEarth()
        let dt = 6 * 3600.0
        let path = NBody.predictedPath(bodies: bodies, of: 1, dt: dt, steps: 400, pointStride: 400)

        var actual = bodies
        for _ in 0..<400 {
            NBody.step(bodies: &actual, dt: dt)
        }
        let endpoint = try! XCTUnwrap(path.last)
        XCTAssertEqual(simd_distance(endpoint, actual[1].position), 0, accuracy: 1.0)
    }

    // MARK: The integrator's own errors

    private let au = CelestialBody.astronomicalUnit

    /// The relative eccentricity vector of bodies[1] about bodies[0], and the orbit normal.
    private func eccentricityVector(_ bodies: [CelestialBody], mu: Double)
        -> (e: SIMD3<Double>, h: SIMD3<Double>) {
        let r = bodies[1].position - bodies[0].position
        let v = bodies[1].velocity - bodies[0].velocity
        let h = simd_cross(r, v)
        return (simd_cross(v, h) / mu - simd_normalize(r), h)
    }

    /// Mercury about the Sun, alone, for `orbits` periods at step `h`: the signed turn of
    /// the apse line per orbit (arcseconds, positive with the motion) and the change in e.
    private func apsidalDrift(step h: Double, orbits: Int) -> (perOrbit: Double, eDrift: Double) {
        let a = 0.387 * au
        let mercury = CelestialBody.mercury.onEllipticalOrbit(
            of: .sun, semiMajorAxis: a, eccentricity: 0.2056, inclination: 0)
        var bodies = [CelestialBody.sun, mercury]
        let mu = NBody.standardGravitationalParameter(
            primaryMass: CelestialBody.sun.mass, bodyMass: mercury.mass)
        let period = NBody.orbitalPeriod(
            semiMajorAxis: a, centralMass: CelestialBody.sun.mass + mercury.mass)
        let (e0, normal) = eccentricityVector(bodies, mu: mu)
        for _ in 0..<Int((Double(orbits) * period / h).rounded()) {
            NBody.step(bodies: &bodies, dt: h)
        }
        let (e1, _) = eccentricityVector(bodies, mu: mu)
        let turn = atan2(simd_dot(simd_cross(e0, e1), simd_normalize(normal)), simd_dot(e0, e1))
        let arcseconds = 180 / Double.pi * 3600
        return (turn * arcseconds / Double(orbits), simd_length(e1) - simd_length(e0))
    }

    /// An isolated two-body orbit does not precess, so any apsidal drift is the
    /// integrator's. Leapfrog at these two steps (the app's 1× and ≥5× steps)
    /// turned Mercury's apse line 19″ and 119″ per orbit, retrograde — 15× and
    /// 93× the real Newtonian precession from the other planets (~1.3″ per
    /// orbit, prograde) — while conserving energy to 1e-8. Energy is not the test.
    func testIsolatedMercuryDoesNotPrecessNumerically() {
        let coarse = apsidalDrift(step: 21_600, orbits: 20)
        XCTAssertLessThan(abs(coarse.perOrbit), 0.05,
                          "the apse line turns \(coarse.perOrbit)″ per orbit at a 6 h step")
        XCTAssertLessThan(abs(coarse.eDrift), 1e-6, "eccentricity drifted \(coarse.eDrift)")
        let fine = apsidalDrift(step: 8_640, orbits: 20)
        XCTAssertLessThan(abs(fine.perOrbit), 0.01,
                          "the apse line turns \(fine.perOrbit)″ per orbit at the 1× step")
    }

    /// The composition is palindromic: a negative step retraces a positive one to roundoff.
    func testStepIsTimeReversible() {
        var bodies = sunEarth()
        let start = bodies
        let dt = 6 * 3600.0
        for _ in 0..<1000 { NBody.step(bodies: &bodies, dt: dt) }
        for _ in 0..<1000 { NBody.step(bodies: &bodies, dt: -dt) }
        for i in bodies.indices {
            XCTAssertEqual(simd_distance(bodies[i].position, start[i].position), 0, accuracy: 0.1,
                           "\(bodies[i].name) did not come home")
            XCTAssertEqual(simd_distance(bodies[i].velocity, start[i].velocity), 0, accuracy: 1e-6)
        }
    }

    /// A frozen body is an infinite-mass anchor: it attracts, and it does not move.
    func testAFrozenBodyAttractsButDoesNotMove() {
        var bodies = sunEarth()
        let sun = bodies[0]
        for _ in 0..<400 {
            NBody.step(bodies: &bodies, dt: 6 * 3600, frozen: [true, false])
            XCTAssertEqual(simd_distance(bodies[0].position, bodies[1].position) / au, 1.0,
                           accuracy: 1e-3, "Earth left its orbit about a frozen Sun")
        }
        XCTAssertEqual(bodies[0].position, sun.position, "the frozen Sun moved")
        XCTAssertEqual(bodies[0].velocity, sun.velocity)
    }

    /// Σ m·v is a constant of the motion, and the integrator keeps it to roundoff.
    func testTheIntegratorConservesMomentum() {
        var bodies = sunEarth()
        bodies.append(CelestialBody.jupiter.onCircularOrbit(of: .sun, distance: 5.204 * au))
        let start = NBody.momentum(of: bodies)
        for _ in 0..<2000 { NBody.step(bodies: &bodies, dt: 6 * 3600) }
        let scale = bodies.reduce(0) { $0 + $1.mass * simd_length($1.velocity) }
        XCTAssertLessThan(simd_length(NBody.momentum(of: bodies) - start), scale * 1e-12)
    }

    /// Inside the softening floor the potential's slope IS the force; the two
    /// used to disagree there (a 1/r potential over a linear force), so the
    /// energy readout lied exactly where a held body sits.
    func testSofteningPotentialIsConsistentWithItsForce() {
        let s = 5e9
        let floor = 2 * s
        func pair(at r: Double) -> [CelestialBody] {
            var a = CelestialBody.sun
            a.position = .zero
            a.velocity = .zero
            var b = CelestialBody.earth
            b.position = SIMD3(r, 0, 0)
            b.velocity = .zero
            return [a, b]
        }
        for fraction in [0.5, 0.99, 1.01, 2.0] {
            let r = fraction * floor
            let delta = 1e-5 * r
            let slope = (NBody.totalEnergy(bodies: pair(at: r + delta), softening: [s, s])
                         - NBody.totalEnergy(bodies: pair(at: r - delta), softening: [s, s]))
                / (2 * delta)
            let pull = simd_length(NBody.accelerations(bodies: pair(at: r), softening: [s, s])[1])
                * CelestialBody.earth.mass
            XCTAssertEqual(slope, pull, accuracy: pull * 1e-6,
                           "at r = \(fraction) ε the potential's slope and the force disagree")
        }
        let inside = NBody.totalEnergy(bodies: pair(at: floor * (1 - 1e-9)), softening: [s, s])
        let outside = NBody.totalEnergy(bodies: pair(at: floor * (1 + 1e-9)), softening: [s, s])
        XCTAssertEqual(inside, outside, accuracy: abs(outside) * 1e-7,
                       "the potential jumps at the floor")
    }
}
