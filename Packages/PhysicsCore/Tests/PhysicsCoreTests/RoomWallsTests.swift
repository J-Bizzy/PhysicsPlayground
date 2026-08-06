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

    /// A zero-radius reflection leaves the ball exactly ON the plane;
    /// the next step, receding, must NOT strike the back face and undo
    /// the bounce (the trajectory-preview double-hit regression).
    func testReflectedBallOnThePlaneIsNotStruckAgain() {
        let hit = RoomWalls.strike(
            previous: SIMD3(2.0, 1.5, 0), current: SIMD3(1.98, 1.5, 0),
            velocity: SIMD3(-5, 0, 0), radius: 0, restitution: 1.0,
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

    /// A ball already inside the wall's ball-radius shell and still
    /// burrowing inward reflects immediately instead of tunneling.
    func testStartingInsideTheShellStillBounces() {
        let hit = RoomWalls.strike(
            previous: SIMD3(1.97, 1.5, 0),   // 3 cm from the wall, shell is 5 cm
            current: SIMD3(1.99, 1.5, 0),    // burrowing deeper
            velocity: SIMD3(2, 0, 0), radius: 0.05, restitution: 0.5,
            walls: [wall])
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit!.velocity.x, -1.0, accuracy: 1e-12)
        XCTAssertEqual(hit!.position.x, 1.95, accuracy: 1e-9,
                       "pushed back to the shell surface")
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

    // MARK: The 2026-08-06 reliability pass

    /// A ceiling graze: the chord crosses the plane inside the step but
    /// gravity has already flipped v·n by the frame's end. The old
    /// guard read that END-OF-FRAME velocity and skipped the strike its
    /// own chord had made — the next step then started past the plane,
    /// which is the tunnel every "the bouncing is unreliable" report
    /// begins with. Approach is a position claim now.
    func testGrazeWhoseVelocityFlippedMidFrameStillStrikes() {
        let ceiling = RoomWalls.Wall(
            center: SIMD3(0, 3, 0), normal: SIMD3(0, -1, 0),
            uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 0, 1),
            halfU: 3, halfV: 3)
        // Rose through y = 3 during the step; end velocity already falls.
        let hit = RoomWalls.strike(
            previous: SIMD3(0, 2.90, 0), current: SIMD3(0, 3.02, 0),
            velocity: SIMD3(1, -0.2, 0), radius: 0.05, restitution: 0.6,
            walls: [ceiling])
        XCTAssertNotNil(hit, "the chord crossed; the graze must strike")
        XCTAssertLessThanOrEqual(hit!.position.y, 3 - 0.05 + 1e-9,
                                 "contact leaves the ball on the room side")
        // The reflection clamps a receding normal component at zero:
        // nothing may ADD speed into the wall it is leaving.
        XCTAssertEqual(hit!.velocity.y, -0.2, accuracy: 1e-12)
        XCTAssertEqual(hit!.impactSpeed, 0, accuracy: 1e-12)
    }

    /// Hand-throw speeds against real frame rates: whenever the chord
    /// reaches the wall, the strike lands and the ball never ends past
    /// the plane — the sweep that pins "reliable" as arithmetic.
    func testFastCrossingsNeverEndPastThePlane() {
        let radius = 0.05
        for speed in [1.0, 5.0, 12.0, 30.0] {
            for dt in [1.0 / 240, 1.0 / 90, 1.0 / 30] {
                let previous = SIMD3(1.0, 1.5, 0.0)
                let velocity = SIMD3(speed, 0, 0)
                let current = previous + velocity * dt
                guard current.x >= 2 - radius else { continue }  // never reached
                let hit = RoomWalls.strike(
                    previous: previous, current: current,
                    velocity: velocity, radius: radius, restitution: 0.7,
                    walls: [wall])
                XCTAssertNotNil(hit, "\(speed) m/s at dt \(dt) tunnelled")
                XCTAssertLessThanOrEqual(hit!.position.x, 2 - radius + 1e-9,
                                         "\(speed) m/s at dt \(dt) ended past the plane")
                XCTAssertEqual(hit!.velocity.x, -0.7 * speed, accuracy: 1e-9,
                               "|v_n'| = e·|v_n| exactly")
            }
        }
    }

    /// `Hit.t` is the fraction of the step spent reaching the wall —
    /// what the model uses to spend the REST of the frame along the
    /// reflection instead of freezing the ball at contact.
    func testHitReportsTheStepFractionConsumed() {
        let hit = RoomWalls.strike(
            previous: SIMD3(1.75, 1.5, 0), current: SIMD3(2.15, 1.5, 0),
            velocity: SIMD3(4, 0, 0), radius: 0.05, restitution: 1,
            walls: [wall])
        XCTAssertNotNil(hit)
        // Contact surface at x = 1.95: half the 0.4 m chord.
        XCTAssertEqual(hit!.t, 0.5, accuracy: 1e-9)
    }

    /// A wall translated into a shifted frame strikes where the frame
    /// says, not where the world does — the lab-relocation case.
    func testTranslatedWallStrikesInItsOwnFrame() {
        let shifted = wall.translated(by: SIMD3(-1, 0, 0))   // plane now at x = 1
        XCTAssertEqual(shifted.center.x, 1, accuracy: 1e-12)
        XCTAssertEqual(shifted.normal, wall.normal, "directions do not translate")
        let hit = RoomWalls.strike(
            previous: SIMD3(0.5, 1.5, 0), current: SIMD3(1.1, 1.5, 0),
            velocity: SIMD3(3, 0, 0), radius: 0.05, restitution: 0.5,
            walls: [shifted])
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit!.position.x, 0.95, accuracy: 1e-9)
    }
}
