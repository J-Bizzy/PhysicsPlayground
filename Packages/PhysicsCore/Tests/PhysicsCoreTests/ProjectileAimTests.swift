//
//  ProjectileAimTests.swift
//  PhysicsCoreTests
//
//  The projectile problem solved backwards: which angles reach a given
//  point. The vacuum roots are checked against the simulation, not
//  against themselves: each angle is fired and the arc must pass through
//  the target. The drag roots are found numerically and held to the
//  looser tolerance the readout discloses.
//

import XCTest
import simd
@testable import PhysicsCore

final class ProjectileAimTests: XCTestCase {

    private let g = 9.81

    /// Height reached at horizontal distance `x`, relative to the launch
    /// point. Launched from a kilometre up so `simulate`'s floor cannot
    /// end an arc bound for a target below the muzzle.
    private func heightAt(x: Double, angle: Double, speed: Double,
                          drag: ProjectileMotion.Drag? = nil, radius: Double = 0) -> Double? {
        let start = SIMD3<Double>(0, 1000, 0)
        let velocity = SIMD3(speed * cos(angle), speed * sin(angle), 0)
        let arc = ProjectileMotion.simulate(
            from: start, launchVelocity: velocity, gravity: g, drag: drag,
            maxBounces: 0, radius: radius, timeStep: 1.0 / 240.0,
            maxDuration: 30, pointStride: 1)
        return ProjectileMotion.heightWhenReaching(horizontal: x, along: arc, from: start)
            .map { $0 - start.y }
    }

    // MARK: Vacuum — both roots land

    func testBothVacuumRootsPassThroughTheTarget() throws {
        let x = 4.0, y = 0.6, v = 9.0
        let angles = try XCTUnwrap(ProjectileMotion.launchAngles(
            toReachHorizontal: x, vertical: y, speed: v, gravity: g))
        XCTAssertLessThan(angles.low, angles.high)
        for angle in [angles.low, angles.high] {
            let height = try XCTUnwrap(heightAt(x: x, angle: angle, speed: v))
            XCTAssertEqual(height, y, accuracy: 1e-3,
                           "the arc at \(angle * 180 / .pi)° misses the target by more than a millimetre")
        }
    }

    /// A target at the maximum range for the speed is reached by exactly
    /// one angle, 45° — the two roots coincide there.
    func testMaximumRangeCollapsesTheRootsOnto45Degrees() throws {
        let v = 7.0
        let x = v * v / g
        let angles = try XCTUnwrap(ProjectileMotion.launchAngles(
            toReachHorizontal: x, vertical: 0, speed: v, gravity: g))
        XCTAssertEqual(angles.low, .pi / 4, accuracy: 1e-6)
        XCTAssertEqual(angles.high, .pi / 4, accuracy: 1e-6)
    }

    func testBeyondRangeHasNoSolution() {
        let v = 7.0
        XCTAssertNil(ProjectileMotion.launchAngles(
            toReachHorizontal: v * v / g * 1.01, vertical: 0, speed: v, gravity: g))
        XCTAssertNil(ProjectileMotion.launchAngles(
            toReachHorizontal: 1, vertical: 30, speed: v, gravity: g),
            "far too high for the speed")
    }

    /// Below the muzzle a low target is always reachable, and the low
    /// root points down.
    func testATargetBelowTheMuzzleIsReachedByADownwardLowRoot() throws {
        let angles = try XCTUnwrap(ProjectileMotion.launchAngles(
            toReachHorizontal: 2, vertical: -1.5, speed: 4, gravity: g))
        XCTAssertLessThan(angles.low, 0)
        let height = try XCTUnwrap(heightAt(x: 2, angle: angles.low, speed: 4))
        XCTAssertEqual(height, -1.5, accuracy: 1e-3)
    }

    func testZeroGravityIsAStraightLine() throws {
        let angles = try XCTUnwrap(ProjectileMotion.launchAngles(
            toReachHorizontal: 3, vertical: 3, speed: 2, gravity: 0))
        XCTAssertEqual(angles.low, .pi / 4, accuracy: 1e-12)
        XCTAssertEqual(angles.high, .pi / 4, accuracy: 1e-12)
    }

    func testStraightUpNeedsEnoughSpeed() {
        // v² = 2gy is exactly enough to arrive with no speed to spare.
        let y = 1.0
        XCTAssertNotNil(ProjectileMotion.launchAngles(
            toReachHorizontal: 0, vertical: y, speed: (2 * g * y).squareRoot(), gravity: g))
        XCTAssertNil(ProjectileMotion.launchAngles(
            toReachHorizontal: 0, vertical: y, speed: (2 * g * y).squareRoot() * 0.99, gravity: g))
        XCTAssertNotNil(ProjectileMotion.launchAngles(
            toReachHorizontal: 0, vertical: -y, speed: 0.1, gravity: g),
            "straight down is reachable at any speed")
    }

    // MARK: With drag — found, not derived

    func testDragRootsPassThroughTheTargetAndDifferFromVacuum() throws {
        let ball = Projectile.tableTennisBall     // the draggiest thing on the bench
        let drag = ProjectileMotion.Drag(projectile: ball)
        let x = 2.5, y = 0.3, v = 8.0
        let vacuum = try XCTUnwrap(ProjectileMotion.launchAngles(
            toReachHorizontal: x, vertical: y, speed: v, gravity: g))
        let withAir = try XCTUnwrap(ProjectileMotion.launchAnglesWithDrag(
            toReachHorizontal: x, vertical: y, speed: v, gravity: g,
            drag: drag, radius: ball.diameter / 2))

        XCTAssertLessThan(withAir.low, withAir.high)
        for angle in [withAir.low, withAir.high] {
            let height = try XCTUnwrap(heightAt(x: x, angle: angle, speed: v,
                                                drag: drag, radius: ball.diameter / 2))
            XCTAssertEqual(height, y, accuracy: 1e-3,
                           "the drag arc at \(angle * 180 / .pi)° misses by more than a millimetre")
        }
        // Air makes the ball fall short, so both roots move up from the
        // vacuum answer: the low arc lifts to compensate, the high arc
        // (which spends longer in the air) more so.
        XCTAssertGreaterThan(withAir.low, vacuum.low)
    }

    func testDragSearchAdmitsDefeatOutOfRange() {
        let ball = Projectile.tableTennisBall
        XCTAssertNil(ProjectileMotion.launchAnglesWithDrag(
            toReachHorizontal: 40, vertical: 0, speed: 8, gravity: g,
            drag: ProjectileMotion.Drag(projectile: ball), radius: ball.diameter / 2))
    }
}
