//
//  NBodyTests.swift
//  The gravity engine pinned to classical results: stable orbits, energy conservation, Kepler III.
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
}
