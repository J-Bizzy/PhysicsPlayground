//
//  SurfaceGravityTests.swift
//  PhysicsCoreTests
//
//  The presets are quoted figures rather than derived ones, which is a
//  claim worth checking: quoting is how a wrong number gets in and stays.
//  So each is compared against GM/R² from the same `CelestialBody` data
//  the orrery uses — agreeing closely where it should, and disagreeing by
//  a known, explained amount for Jupiter.
//

import XCTest
@testable import PhysicsCore

final class SurfaceGravityTests: XCTestCase {

    /// g = GM/R² for a non-rotating sphere of a body's mass and radius.
    private func newtonianSurfaceGravity(_ body: CelestialBody) -> Double {
        NBody.gravitationalConstant * body.mass / (body.radius * body.radius)
    }

    /// Earth's quoted 9.81 is GM/R² to within a fraction of a percent —
    /// Earth turns slowly enough that rotation barely enters.
    func testEarthMatchesNewtonianGravity() {
        let derived = newtonianSurfaceGravity(.earth)
        XCTAssertEqual(SurfaceGravity.earth.gravity, derived, accuracy: 0.05,
                       "9.81 should be GM/R² for Earth's mass and radius")
    }

    /// The Moon does not rotate fast enough to matter either.
    func testMoonMatchesNewtonianGravity() {
        let derived = newtonianSurfaceGravity(.moon)
        XCTAssertEqual(SurfaceGravity.moon.gravity, derived, accuracy: 0.02)
    }

    /// Jupiter's quoted 24.79 is GM/R² at its EQUATORIAL radius, not at
    /// the volumetric mean radius `CelestialBody` stores. Jupiter is
    /// oblate enough (71,492 km across the equator vs a 69,911 km mean)
    /// that which radius you use moves the answer by 4.6%.
    ///
    /// This test replaced one asserting the gap was centrifugal. It
    /// wasn't: the shortfall is 1.13 m/s² and ω²R is 2.16, so rotation
    /// flattens the planet here rather than cancelling the gravity.
    func testJupiterMatchesNewtonianGravityAtItsEquatorialRadius() {
        let equatorialRadius = 7.1492e7
        let atEquator = NBody.gravitationalConstant * CelestialBody.jupiter.mass
            / (equatorialRadius * equatorialRadius)
        XCTAssertEqual(SurfaceGravity.jupiter.gravity, atEquator, accuracy: 0.02,
                       "24.79 is GM/R² with the equatorial radius")

        // And it is genuinely below the mean-radius figure, which is why
        // the naive check fails.
        XCTAssertLessThan(SurfaceGravity.jupiter.gravity,
                          newtonianSurfaceGravity(.jupiter))
    }

    /// The mean radius stored for Jupiter really is the smaller, oblate
    /// one — if someone "fixes" it to the equatorial value, the orrery's
    /// geometry changes and this preset stops matching its own derivation.
    func testJupiterStoredRadiusIsTheVolumetricMean() {
        XCTAssertEqual(CelestialBody.jupiter.radius, 6.9911e7, accuracy: 1e4)
        XCTAssertLessThan(CelestialBody.jupiter.radius, 7.1492e7)
    }

    /// Ordering is the pedagogy: the same throw on three worlds only
    /// teaches anything if they are genuinely different and correctly
    /// ranked.
    func testWorldsAreOrderedWeakestFirst() {
        let values = SurfaceGravity.bodies.map(\.gravity)
        XCTAssertEqual(values, values.sorted(), "Moon < Earth < Jupiter")
        XCTAssertLessThan(SurfaceGravity.moon.gravity, SurfaceGravity.earth.gravity)
        XCTAssertLessThan(SurfaceGravity.earth.gravity, SurfaceGravity.jupiter.gravity)
    }

    /// Zero-g belongs to `all` and not to `bodies` — a pendulum bench
    /// offering it would be offering a pendulum that cannot swing.
    func testZeroGIsSeparatedFromTheRealBodies() {
        XCTAssertEqual(SurfaceGravity.zeroG.gravity, 0)
        XCTAssertFalse(SurfaceGravity.bodies.contains(SurfaceGravity.zeroG))
        XCTAssertTrue(SurfaceGravity.all.contains(SurfaceGravity.zeroG))
        XCTAssertEqual(SurfaceGravity.all.count, SurfaceGravity.bodies.count + 1)
        XCTAssertEqual(SurfaceGravity.all.first, SurfaceGravity.zeroG)
    }

    /// Every preset must be inside the range the labs expose, or a button
    /// would set a value its own slider cannot represent.
    func testAllPresetsAreNonNegativeAndFinite() {
        for world in SurfaceGravity.all {
            XCTAssertGreaterThanOrEqual(world.gravity, 0, world.name)
            XCTAssertTrue(world.gravity.isFinite, world.name)
            XCTAssertFalse(world.name.isEmpty)
        }
    }
}
