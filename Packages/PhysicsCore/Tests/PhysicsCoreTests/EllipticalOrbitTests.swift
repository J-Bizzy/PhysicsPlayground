//
//  EllipticalOrbitTests.swift
//  PhysicsCoreTests
//
//  The inclined comet orbit has to be a real Kepler orbit, not a
//  decorative tilt: perihelion distance, perihelion speed and the
//  resulting semi-major axis all have to come back out of the state
//  vector the builder produces.
//

import XCTest
import simd
@testable import PhysicsCore

final class EllipticalOrbitTests: XCTestCase {

    private let sun = CelestialBody.sun
    private let au = CelestialBody.astronomicalUnit
    private let G = NBody.gravitationalConstant

    /// e = 0 must reduce EXACTLY to the circular-orbit builder — the
    /// standard "does the general case contain the special one" check.
    func testZeroEccentricityReducesToACircularOrbit() {
        let circular = CelestialBody.earth.onCircularOrbit(of: sun, distance: au)
        let elliptical = CelestialBody.earth.onEllipticalOrbit(
            of: sun, semiMajorAxis: au, eccentricity: 0, inclination: 0)
        XCTAssertEqual(simd_distance(circular.position, elliptical.position), 0,
                       accuracy: 1e-3)
        XCTAssertEqual(simd_length(circular.velocity), simd_length(elliptical.velocity),
                       accuracy: 1e-6)
    }

    /// Perihelion distance is a(1−e), exactly.
    func testStartsAtPerihelion() {
        let a = 17.834 * au, e = 0.967
        let comet = CelestialBody.comet.onEllipticalOrbit(
            of: sun, semiMajorAxis: a, eccentricity: e, inclination: 0.5)
        let r = simd_distance(comet.position, sun.position)
        XCTAssertEqual(r, a * (1 - e), accuracy: a * 1e-12)
    }

    /// At perihelion the velocity is perpendicular to the radius — the
    /// defining property of an apsis.
    func testVelocityIsPerpendicularToTheRadiusAtPerihelion() {
        let comet = CelestialBody.comet.onEllipticalOrbit(
            of: sun, semiMajorAxis: 17.834 * au, eccentricity: 0.967,
            inclination: 162 * .pi / 180)
        let radial = simd_normalize(comet.position - sun.position)
        let velocity = simd_normalize(comet.velocity - sun.velocity)
        XCTAssertEqual(simd_dot(radial, velocity), 0, accuracy: 1e-12)
    }

    /// The real test: feed the state vector back through vis-viva and
    /// recover the semi-major axis you asked for. 1/a = 2/r − v²/GM.
    func testVisVivaRecoversTheRequestedSemiMajorAxis() {
        for (aAU, e) in [(17.834, 0.967), (3.0, 0.4), (1.0, 0.0167)] {
            let a = aAU * au
            let comet = CelestialBody.comet.onEllipticalOrbit(
                of: sun, semiMajorAxis: a, eccentricity: e, inclination: 1.1)
            let r = simd_distance(comet.position, sun.position)
            let v2 = simd_length_squared(comet.velocity - sun.velocity)
            let recovered = 1 / (2 / r - v2 / (G * sun.mass))
            XCTAssertEqual(recovered / a, 1, accuracy: 1e-9,
                           "vis-viva must give back a = \(aAU) AU")
        }
    }

    /// An inclined orbit genuinely leaves the ecliptic: the specific
    /// angular momentum tilts away from the planets' orbit normal by
    /// exactly the requested inclination.
    func testInclinationTiltsTheOrbitPlaneByExactlyThatAngle() {
        for degrees in [0.0, 30.0, 90.0, 162.0] {
            let inclination = degrees * .pi / 180
            let comet = CelestialBody.comet.onEllipticalOrbit(
                of: sun, semiMajorAxis: 5 * au, eccentricity: 0.8,
                inclination: inclination)
            let h = simd_cross(comet.position - sun.position, comet.velocity - sun.velocity)
            // The planets orbit in the xz plane (+x, moving −z), whose
            // angular-momentum direction is +y.
            let cosine = simd_dot(simd_normalize(h), SIMD3<Double>(0, 1, 0))
            XCTAssertEqual(acos(min(max(cosine, -1), 1)), inclination, accuracy: 1e-9)
        }
    }

    /// Retrograde really is retrograde: past 90° the orbit runs the
    /// opposite way round from the planets.
    func testRetrogradeInclinationReversesTheSenseOfTheOrbit() {
        let comet = CelestialBody.comet.onEllipticalOrbit(
            of: sun, semiMajorAxis: 17.834 * au, eccentricity: 0.967,
            inclination: 162 * .pi / 180)
        let h = simd_cross(comet.position - sun.position, comet.velocity - sun.velocity)
        XCTAssertLessThan(h.y, 0, "angular momentum points against the planets'")
    }
}
