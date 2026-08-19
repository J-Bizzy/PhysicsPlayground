//
//  LagrangeTests.swift
//  Lagrange points pinned to published values, exact geometry, and L4's genuine stability.
//

import XCTest
import simd
@testable import PhysicsCore

final class LagrangeTests: XCTestCase {

    private func earthMoonPoints() -> (Lagrange.Points, CelestialBody, CelestialBody) {
        let (earth, moon) = Lagrange.earthMoonSystem()
        return (Lagrange.points(primary: earth, secondary: moon), earth, moon)
    }

    /// Published: Earth–Moon L1 ≈ 326,400 km, L2 ≈ 448,900 km from Earth.
    func testEarthMoonColinearPointsMatchPublishedValues() {
        let (points, earth, _) = earthMoonPoints()
        let l1FromEarth = simd_distance(points.l1, earth.position)
        let l2FromEarth = simd_distance(points.l2, earth.position)
        XCTAssertEqual(l1FromEarth, 3.264e8, accuracy: 3.264e8 * 0.01)
        XCTAssertEqual(l2FromEarth, 4.489e8, accuracy: 4.489e8 * 0.01)
    }

    /// Sun–Earth L1 (SOHO's home) sits ≈ 1.49 million km sunward of Earth.
    func testSunEarthL1MatchesPublishedValue() {
        let sun = CelestialBody.sun
        let earth = CelestialBody.earth.onCircularOrbit(
            of: sun, distance: CelestialBody.astronomicalUnit)
        let points = Lagrange.points(primary: sun, secondary: earth)
        let l1FromEarth = simd_distance(points.l1, earth.position)
        XCTAssertEqual(l1FromEarth, 1.4911e9, accuracy: 1.4911e9 * 0.01)
    }

    func testL4L5AreEquilateral() {
        let (points, earth, moon) = earthMoonPoints()
        let separation = simd_distance(earth.position, moon.position)
        for point in [points.l4, points.l5] {
            XCTAssertEqual(simd_distance(point, earth.position), separation,
                           accuracy: separation * 1e-9)
            XCTAssertEqual(simd_distance(point, moon.position), separation,
                           accuracy: separation * 1e-9)
        }
        XCTAssertGreaterThan(simd_distance(points.l4, points.l5), separation,
                             "L4 and L5 sit on opposite sides of the axis")
    }

    func testL3IsOppositeTheSecondary() {
        let (points, earth, moon) = earthMoonPoints()
        let toMoon = moon.position - earth.position
        let toL3 = points.l3 - earth.position
        XCTAssertLessThan(simd_dot(toMoon, toL3), 0, "L3 is on the opposite side")
        let separation = simd_length(toMoon)
        XCTAssertEqual(simd_length(toL3), separation, accuracy: separation * 0.01)
    }

    /// A co-rotating satellite stays near the moving L4 for a lunar month — L4 is genuinely stable.
    func testSatelliteAtL4StaysThereForAMonth() {
        var (earth, moon) = Lagrange.earthMoonSystem()
        let points = Lagrange.points(primary: earth, secondary: moon)
        var satellite = CelestialBody(name: "Satellite", mass: 1e3, radius: 2)
        satellite.position = points.l4
        satellite.velocity = Lagrange.corotatingVelocity(
            at: points.l4, primary: earth, secondary: moon)

        var bodies = [earth, moon, satellite]
        let separation = simd_distance(earth.position, moon.position)
        let dt = 240.0
        let month = 27.3 * 86_400

        var time = 0.0
        while time < month {
            NBody.step(bodies: &bodies, dt: dt)
            time += dt
        }
        earth = bodies[0]
        moon = bodies[1]
        let currentL4 = Lagrange.points(primary: earth, secondary: moon).l4
        let drift = simd_distance(bodies[2].position, currentL4)
        XCTAssertLessThan(drift, 0.05 * separation,
                          "after a month the satellite has drifted \(drift / separation) separations from L4")
    }

    /// Contrast: L1 is an unstable saddle — a 0.1% nudge drifts visibly.
    func testSatelliteAtL1DriftsAway() {
        var (earth, moon) = Lagrange.earthMoonSystem()
        let points = Lagrange.points(primary: earth, secondary: moon)
        var satellite = CelestialBody(name: "Satellite", mass: 1e3, radius: 2)
        satellite.position = points.l1 * 1.001
        satellite.velocity = Lagrange.corotatingVelocity(
            at: satellite.position, primary: earth, secondary: moon)

        var bodies = [earth, moon, satellite]
        let separation = simd_distance(earth.position, moon.position)
        let dt = 240.0
        var time = 0.0
        while time < 27.3 * 86_400 {
            NBody.step(bodies: &bodies, dt: dt)
            time += dt
        }
        earth = bodies[0]
        moon = bodies[1]
        let currentL1 = Lagrange.points(primary: earth, secondary: moon).l1
        XCTAssertGreaterThan(simd_distance(bodies[2].position, currentL1),
                             0.1 * separation,
                             "L1 must not hold a satellite without station-keeping")
    }
}
