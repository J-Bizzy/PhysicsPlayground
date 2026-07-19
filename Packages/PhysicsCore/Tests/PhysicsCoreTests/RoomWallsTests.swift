//
//  RoomWallsTests.swift
//  PhysicsCoreTests
//
//  The wall bounce obeys the same impulse law as the floor: normal
//  component reversed and scaled by restitution, tangential component
//  untouched. Walls are finite rectangles and two-sided.
//

import XCTest
import simd
@testable import PhysicsCore

final class RoomWallsTests: XCTestCase {

    /// A wall at x = 2 facing the origin.
    private let wall = RoomWalls.Wall(
        center: SIMD3(2, 1.5, 0), normal: SIMD3(1, 0, 0),
        uAxis: SIMD3(0, 0, 1), vAxis: SIMD3(0, 1, 0),
        halfU: 1.5, halfV: 1.5)

    /// Head-on: v' = v − (1+e)(v·n)n exactly; tangential survives.
    func testBounceReflectsNormalScaledByRestitution() {
        let hit = RoomWalls.strike(
            previous: SIMD3(1.5, 1.5, 0), current: SIMD3(2.05, 1.5, 0),
            velocity: SIMD3(3, 1, 2), radius: 0.05, restitution: 0.5,
            walls: [wall])
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit!.velocity.x, -1.5, accuracy: 1e-12,
                       "normal component reverses at ×e")
        XCTAssertEqual(hit!.velocity.y, 1, accuracy: 1e-12)
        XCTAssertEqual(hit!.velocity.z, 2, accuracy: 1e-12)
        XCTAssertEqual(hit!.impactSpeed, 3, accuracy: 1e-12)
        // Contact puts the ball's surface on the wall: center at x = 2 − r.
        XCTAssertEqual(hit!.position.x, 1.95, accuracy: 1e-9)
    }

    /// The same wall struck from the far side bounces the other way —
    /// anchors' normal conventions can never break the physics.
    func testWallsAreTwoSided() {
        let hit = RoomWalls.strike(
            previous: SIMD3(2.5, 1.5, 0), current: SIMD3(1.95, 1.5, 0),
            velocity: SIMD3(-3, 0, 0), radius: 0.05, restitution: 1.0,
            walls: [wall])
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit!.velocity.x, 3, accuracy: 1e-12)
    }

    /// A crossing outside the rectangle's extent misses — walls are
    /// finite, not infinite planes.
    func testMissesBeyondTheWallExtent() {
        let hit = RoomWalls.strike(
            previous: SIMD3(1.5, 4.0, 0), current: SIMD3(2.05, 4.0, 0),
            velocity: SIMD3(3, 0, 0), radius: 0.05, restitution: 0.5,
            walls: [wall])
        XCTAssertNil(hit, "y = 4 is above the wall's top edge")
    }

    /// No crossing, no hit.
    func testNoStrikeWithoutCrossing() {
        let hit = RoomWalls.strike(
            previous: SIMD3(1.0, 1.5, 0), current: SIMD3(1.5, 1.5, 0),
            velocity: SIMD3(3, 0, 0), radius: 0.05, restitution: 0.5,
            walls: [wall])
        XCTAssertNil(hit)
    }

    /// The trajectory simulation reflects off walls with the same law
    /// as live flights: elastic wall at x = 2, horizontal launch — the
    /// path never passes the wall and comes back at full speed.
    func testSimulatedTrajectoryBouncesOffWalls() {
        let trajectory = ProjectileMotion.simulate(
            from: SIMD3(0, 1.5, 0),
            launchVelocity: SIMD3(5, 0, 0),
            gravity: 9.81,
            restitution: 1.0,
            maxBounces: 4,
            walls: [wall],
            maxDuration: 2
        )
        let maxX = trajectory.points.map(\.x).max()!
        XCTAssertLessThanOrEqual(maxX, 2.0 + 1e-9, "never passes the wall plane")
        XCTAssertGreaterThan(maxX, 1.99, "actually reaches the wall")
        XCTAssertLessThan(trajectory.points.last!.x, 1.0,
                          "came back off the wall")
    }

    /// Two walls in the path: the strike reports the FIRST one hit.
    func testEarliestWallWins() {
        let near = RoomWalls.Wall(
            center: SIMD3(1.5, 1.5, 0), normal: SIMD3(1, 0, 0),
            uAxis: SIMD3(0, 0, 1), vAxis: SIMD3(0, 1, 0),
            halfU: 1.5, halfV: 1.5)
        let hit = RoomWalls.strike(
            previous: SIMD3(1.0, 1.5, 0), current: SIMD3(2.2, 1.5, 0),
            velocity: SIMD3(3, 0, 0), radius: 0.05, restitution: 0.5,
            walls: [wall, near])
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit!.position.x, 1.45, accuracy: 1e-9,
                       "stopped at the nearer wall")
    }
}
