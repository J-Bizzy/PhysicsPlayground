//
//  SphereStrikeTests.swift
//  PhysicsCoreTests
//
//  The swat (Projectiles, 2026-09-02): a ball against a moving sphere.
//  Pinned by the numbers a swat has to produce, not by matching the
//  implementation to itself.
//

import XCTest
import simd
@testable import PhysicsCore

final class SphereStrikeTests: XCTestCase {

    /// A resting ball hit by a hand moving at 3 m/s leaves along the
    /// hand's line at 3·(1 + e): the relative bounce plus the hand's own
    /// motion.
    func testARestingBallLeavesAtTheHandsSpeedTimesOnePlusRestitution() throws {
        let ball = SIMD3<Double>(0, 1, 0)
        let hand = SphereStrike.Sphere(center: SIMD3(-0.06, 1, 0), radius: 0.03,
                                       velocity: SIMD3(3, 0, 0))
        let hit = try XCTUnwrap(SphereStrike.strike(
            previous: ball, current: ball, velocity: .zero,
            radius: 0.04, restitution: 0.8, spheres: [hand]))
        XCTAssertEqual(hit.velocity.x, 3 * 1.8, accuracy: 1e-9)
        XCTAssertEqual(hit.velocity.y, 0, accuracy: 1e-9)
        XCTAssertEqual(hit.impactSpeed, 3, accuracy: 1e-9)
        XCTAssertEqual(hit.t, 0, "already touching: resolved now")
        XCTAssertEqual(hit.position.x, -0.06 + 0.07, accuracy: 1e-9,
                       "pushed to the surface, its radius out along the normal")
    }

    /// The sweep. A hand swung at 12 m/s crosses 13 cm in a 90 Hz frame
    /// — more than twice a golf ball's reach — so it can END the frame
    /// on the far side of a ball it never overlapped at a boundary.
    /// Without the sphere's own motion that is a miss (the hand
    /// tunnelled through); with it, the relative path crosses the ball
    /// and the strike lands at the moment it happened.
    func testAFastHandSweepingThroughABallStrikesIt() throws {
        let ball = SIMD3<Double>(0, 1, 0)
        // Ends 2 mm clear of the ball on the FAR side …
        let hand = SphereStrike.Sphere(center: SIMD3(0.053, 1, 0), radius: 0.03,
                                       velocity: SIMD3(12, 0, 0))
        // … so as a static sphere it is not touching:
        XCTAssertNil(SphereStrike.strike(
            previous: ball, current: ball, velocity: .zero,
            radius: 0.021, restitution: 0.8, spheres: [hand]))
        // With the frame's sweep it started 13 cm back and passed through.
        let hit = try XCTUnwrap(SphereStrike.strike(
            previous: ball, current: ball, velocity: .zero,
            radius: 0.021, restitution: 0.8, spheres: [hand], dt: 1.0 / 90.0))
        XCTAssertEqual(hit.velocity.x, 12 * 1.8, accuracy: 1e-9)
        XCTAssertGreaterThan(hit.t, 0)
        XCTAssertLessThan(hit.t, 1)
    }

    /// And when the two DO overlap at the boundary, the sweep still
    /// places the contact where and when it happened rather than
    /// teleporting the ball out of the hand at t = 0.
    func testTheSweepPlacesTheContactWhereItHappened() throws {
        let ball = SIMD3<Double>(0, 1, 0)
        let hand = SphereStrike.Sphere(center: SIMD3(-0.045, 1, 0), radius: 0.03,
                                       velocity: SIMD3(4, 0, 0))
        let unswept = try XCTUnwrap(SphereStrike.strike(
            previous: ball, current: ball, velocity: .zero,
            radius: 0.021, restitution: 0.8, spheres: [hand]))
        XCTAssertEqual(unswept.t, 0)
        XCTAssertEqual(unswept.position.x, 0.006, accuracy: 1e-9, "pushed out of the overlap")

        let swept = try XCTUnwrap(SphereStrike.strike(
            previous: ball, current: ball, velocity: .zero,
            radius: 0.021, restitution: 0.8, spheres: [hand], dt: 1.0 / 90.0))
        XCTAssertGreaterThan(swept.t, 0.5)
        XCTAssertEqual(swept.position.x, 0, accuracy: 1e-9,
                       "the ball is met where it stood, at the moment the hand arrived")
    }

    /// The tangential component survives; only the normal one reflects.
    /// The path runs straight down onto the sphere's pole so the contact
    /// normal is exactly +y and the numbers are exact.
    func testOnlyTheNormalComponentReflects() throws {
        let previous = SIMD3<Double>(0, 0.20, 0)
        let current = SIMD3<Double>(0, 0.05, 0)
        let sphere = SphereStrike.Sphere(center: .zero, radius: 0.10)
        let hit = try XCTUnwrap(SphereStrike.strike(
            previous: previous, current: current, velocity: SIMD3(1, -1, 0),
            radius: 0.02, restitution: 0.5, spheres: [sphere]))
        XCTAssertEqual(hit.velocity.x, 1, accuracy: 1e-9)
        XCTAssertEqual(hit.velocity.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(hit.position.y, 0.12, accuracy: 1e-9)
        XCTAssertGreaterThan(hit.t, 0)
        XCTAssertLessThan(hit.t, 1)
    }

    /// Moving away from a sphere it is touching is not a strike.
    func testASeparatingBallIsLeftAlone() {
        let sphere = SphereStrike.Sphere(center: .zero, radius: 0.1)
        XCTAssertNil(SphereStrike.strike(
            previous: SIMD3(0.12, 0, 0), current: SIMD3(0.2, 0, 0),
            velocity: SIMD3(2, 0, 0), radius: 0.03, restitution: 0.8, spheres: [sphere]))
    }

    func testAMissIsAMiss() {
        let sphere = SphereStrike.Sphere(center: .zero, radius: 0.1)
        XCTAssertNil(SphereStrike.strike(
            previous: SIMD3(-1, 0.5, 0), current: SIMD3(1, 0.5, 0),
            velocity: SIMD3(2, 0, 0), radius: 0.03, restitution: 0.8, spheres: [sphere]))
    }

    /// Two spheres in the path: the earlier contact wins.
    func testTheEarliestContactWins() throws {
        let near = SphereStrike.Sphere(center: SIMD3(0.3, 0, 0), radius: 0.05)
        let far = SphereStrike.Sphere(center: SIMD3(0.8, 0, 0), radius: 0.05)
        let hit = try XCTUnwrap(SphereStrike.strike(
            previous: .zero, current: SIMD3(1, 0, 0), velocity: SIMD3(5, 0, 0),
            radius: 0.02, restitution: 1, spheres: [far, near]))
        XCTAssertEqual(hit.position.x, 0.3 - 0.07, accuracy: 1e-9)
        XCTAssertEqual(hit.velocity.x, -5, accuracy: 1e-9)
    }
}
