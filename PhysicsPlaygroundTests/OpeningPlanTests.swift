//
//  OpeningPlanTests.swift
//  PhysicsPlaygroundTests
//
//  "Birth of a System" is physics, so it is tested as physics: the disk
//  shears as Kepler says, every world circles at its circular speed until
//  one stated impulse puts it on a transfer that conserves energy and
//  angular momentum and reaches its plinth exactly as the clock comes to
//  rest — and the whole stays watchable: paced, clear of the wearer's
//  face, every world on its own plinth.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

final class OpeningPlanTests: XCTestCase {

    private let plan = OpeningPlan.shared
    private let frame = 1.0 / 90.0

    // MARK: The clock

    func testItRunsSixAndAHalfSecondsAndLandsOnTheBell() {
        XCTAssertGreaterThanOrEqual(OpeningPlan.duration, 5.5)
        XCTAssertLessThanOrEqual(OpeningPlan.duration, 6.5)
        XCTAssertEqual(OpeningPlan.landingTime, SoundEffects.calibrationLanding, accuracy: 1e-9,
                       "the bell and the landing must be one instant")
        XCTAssertEqual(OpeningPlan.clock.rate(at: OpeningPlan.landingTime), 0, accuracy: 1e-12,
                       "the clock must be at rest as the worlds arrive")
    }

    // MARK: The disk

    /// Each ring turns at Ω = √(GM/r³): two rings' angles stand in the ratio
    /// (r₂/r₁)^(3/2), and orbital speed falls as r^(−1/2).
    func testTheDiskShearsAsKeplerSays() {
        let inner = OpeningPlan.annulus(2), outer = OpeningPlan.annulus(25)
        let r1 = (inner.inner * inner.outer).squareRoot()
        let r2 = (outer.inner * outer.outer).squareRoot()
        let t = 2.7
        XCTAssertEqual(plan.annulusAngle(2, at: t) / plan.annulusAngle(25, at: t),
                       pow(r2 / r1, 1.5), accuracy: 1e-9)
        for r in [0.3, 0.5, 0.9] {
            let speed = OpeningPlan.angularSpeed(atRadius: r) * r
            XCTAssertEqual(speed, (OpeningPlan.gm / r).squareRoot(), accuracy: 1e-12)
        }
        XCTAssertEqual(plan.annulusAngle(10, at: OpeningPlan.spokesStraight), 0, accuracy: 1e-12,
                       "the spokes are straight when the disk has arrived")
    }

    /// Seen from the wearer, the disk is an ellipse 24° from edge-on.
    func testTheDiskIsSeenTwentyFourDegreesFromEdgeOn() {
        let toEye = simd_normalize(OpeningPlan.eye - plan.star)
        XCTAssertEqual(asin(simd_dot(plan.diskNormal, toEye)), OpeningPlan.viewFromEdge, accuracy: 1e-9)
    }

    /// Up after it forms, gone once it clears (inside out), and never seen
    /// turning faster than the eye can follow.
    func testTheDiskComesAndGoesAndNeverSpinsTooFast() {
        for k in 0..<OpeningPlan.annulusCount {
            XCTAssertEqual(plan.annulusOpacity(k, at: OpeningPlan.diskStart - 0.01), 0, accuracy: 1e-9)
            XCTAssertEqual(plan.annulusOpacity(k, at: 4.75), 0, accuracy: 1e-9)
            let bounds = OpeningPlan.annulus(k)
            let omega = OpeningPlan.angularSpeed(atRadius: (bounds.inner * bounds.outer).squareRoot())
            let full = plan.annulusOpacity(k, at: 2.0)
            for t in stride(from: 0.0, through: 5.0, by: 0.01) where plan.annulusOpacity(k, at: t) > 0.05 * full {
                XCTAssertLessThan(omega * OpeningPlan.clock.rate(at: t) / (2 * .pi), 2.5,
                                  "ring \(k) seen spinning past 2.5 turns a second at \(t) s")
            }
        }
        // The innermost clears before the outermost.
        XCTAssertLessThan(plan.annulusOpacity(0, at: 3.6), plan.annulusOpacity(30, at: 3.6))
    }

    // MARK: The worlds

    func testEveryPlinthGetsOneWorldAndTheFarthestTheInnermost() {
        XCTAssertEqual(plan.worlds.count, 7)
        XCTAssertEqual(Set(plan.worlds.map(\.portal)), Set(0..<7))
        let distances = plan.worlds.map { simd_distance($0.landing, plan.star) }
        XCTAssertEqual(distances, distances.sorted(by: >), "rings out must go to plinths in")
    }

    /// Until it leaves, a world is on a circle at exactly √(GM/r).
    func testEveryWorldCirclesAtItsCircularSpeed() {
        for world in plan.worlds {
            for tau in stride(from: 0, to: world.departureSim, by: 0.25) {
                let state = world.ring.state(at: tau)
                XCTAssertEqual(simd_length(state.position), world.ringRadius, accuracy: 1e-9)
                XCTAssertEqual(simd_length(state.velocity), (OpeningPlan.gm / world.ringRadius).squareRoot(),
                               accuracy: 1e-9)
            }
        }
    }

    /// Departure is one impulse: the place is continuous, the velocity
    /// jumps by exactly the stated Δv — at most 0.6 of the circular speed,
    /// turning the path by at most 25°.
    func testDepartureIsOneStatedImpulse() {
        for world in plan.worlds {
            let ring = world.ring.state(at: world.departureSim)
            let transfer = world.transfer.state(at: world.departureSim)
            XCTAssertLessThan(simd_distance(ring.position, transfer.position), 1e-9, world.name)
            XCTAssertLessThan(simd_distance(transfer.velocity - ring.velocity, world.deltaV), 1e-9)
            XCTAssertLessThanOrEqual(simd_length(world.deltaV), 0.6 * simd_length(ring.velocity))
            let turn = acos(min(1, simd_dot(simd_normalize(ring.velocity), simd_normalize(transfer.velocity))))
            XCTAssertLessThanOrEqual(turn, 25 * Double.pi / 180, world.name)
        }
    }

    /// On the transfer only the star acts: energy and angular momentum are
    /// constant, and the world reaches its plinth at its far end — at rest
    /// radially — exactly at the landing.
    func testEveryTransferIsKeplerianAndLandsExactly() {
        for (index, world) in plan.worlds.enumerated() {
            let mu = OpeningPlan.gm
            var energy: Double?, momentum: SIMD3<Double>?
            for tau in stride(from: world.departureSim, through: OpeningPlan.landingSimTime, by: 0.05) {
                let s = world.transfer.state(at: tau)
                let e = simd_length_squared(s.velocity) / 2 - mu / simd_length(s.position)
                let h = simd_cross(s.position, s.velocity)
                if let energy { XCTAssertEqual(e, energy, accuracy: 1e-9) } else { energy = e }
                if let momentum { XCTAssertLessThan(simd_distance(h, momentum), 1e-9) } else { momentum = h }
            }
            let landed = world.transfer.state(at: OpeningPlan.landingSimTime)
            XCTAssertEqual(simd_dot(landed.position, landed.velocity), 0, accuracy: 1e-9,
                           "\(world.name) is still moving radially at the landing")
            XCTAssertLessThan(simd_distance(plan.position(ofWorld: index, at: OpeningPlan.landingTime),
                                            world.landing), 1e-9)
            XCTAssertLessThan(simd_distance(plan.position(ofWorld: index, at: 9), world.landing), 1e-9,
                              "a world must stay where it landed")
        }
    }

    // MARK: Watchable

    /// The worlds form after the disk has, leave one by one, cross the room
    /// at no more than 6 cm a frame, and never jump.
    func testItIsPacedToBeWatched() {
        // Innermost first, near enough: two may leave within 50 ms either way.
        let departures = plan.worlds.map(\.departureWall)
        for (earlier, later) in zip(departures, departures.dropFirst()) {
            XCTAssertLessThan(earlier, later + 0.05, "an outer world left well before an inner one")
        }
        for (index, world) in plan.worlds.enumerated() {
            XCTAssertGreaterThanOrEqual(world.condenseStart, OpeningPlan.diskStart + OpeningPlan.diskRise,
                                        "\(world.name) forms before its disk")
            XCTAssertGreaterThanOrEqual(world.departureWall, 2.0)
            XCTAssertLessThanOrEqual(world.departureWall, 4.5)
            var previous = plan.position(ofWorld: index, at: 0)
            for t in stride(from: frame, through: OpeningPlan.landingTime + frame, by: frame) {
                let now = plan.position(ofWorld: index, at: t)
                if plan.growth(ofWorld: index, at: t) > 0 {
                    XCTAssertLessThanOrEqual(simd_distance(now, previous), 0.06,
                                             "\(world.name) jumps at \(t) s")
                }
                if t < world.departureWall {
                    let spin = OpeningPlan.angularSpeed(atRadius: world.ringRadius)
                        * OpeningPlan.clock.rate(at: t) / (2 * .pi)
                    XCTAssertLessThanOrEqual(spin, 1.5, "\(world.name)'s ring spins too fast at \(t) s")
                }
                previous = now
            }
        }
    }

    /// Nothing comes within 60 cm of the eyes or below a metre, and the
    /// star stands clear of every plinth, the wordmark and the More.
    func testItKeepsClearOfTheWearer() {
        for index in plan.worlds.indices {
            for t in stride(from: 0.0, through: OpeningPlan.landingTime, by: frame)
            where plan.growth(ofWorld: index, at: t) > 0 {
                let p = plan.position(ofWorld: index, at: t)
                XCTAssertGreaterThan(simd_distance(p, OpeningPlan.eye), 0.6)
                XCTAssertGreaterThan(p.y, 1.0)
            }
        }
        let towardStar = simd_normalize(plan.star - OpeningPlan.eye)
        var others = PortalLayout.portals(count: 7).map(PortalLayout.plinthCentre(of:))
        others += [SIMD3(0, 2.12, -2.15), SIMD3(0, 1.80, -2.13)]
        for point in others {
            let angle = acos(simd_dot(towardStar, simd_normalize(point - OpeningPlan.eye)))
            XCTAssertGreaterThan(angle, 5 * Double.pi / 180, "the star stands in front of \(point)")
        }
    }

    /// A world is nothing before it condenses, whole from then to the
    /// landing, and gone into its lab soon after.
    func testAWorldCondensesAndOpensAway() {
        for (index, world) in plan.worlds.enumerated() {
            XCTAssertEqual(plan.growth(ofWorld: index, at: world.condenseStart - 0.01), 0)
            XCTAssertEqual(plan.growth(ofWorld: index, at: world.condenseEnd), 1, accuracy: 1e-12)
            XCTAssertEqual(plan.growth(ofWorld: index, at: OpeningPlan.landingTime), 1, accuracy: 1e-12)
            XCTAssertEqual(plan.growth(ofWorld: index, at: OpeningPlan.landingTime + OpeningPlan.worldOpen),
                           0, accuracy: 1e-12)
        }
    }

    /// A trail is the path flown, in closed form: nothing before the
    /// world leaves, and it ends at the world.
    func testATrailIsThePathFlown() {
        for (index, world) in plan.worlds.enumerated() {
            XCTAssertTrue(plan.trail(ofWorld: index, at: world.departureWall - 0.05).points.isEmpty)
            let t = (world.departureWall + OpeningPlan.landingTime) / 2
            let trail = plan.trail(ofWorld: index, at: t)
            XCTAssertEqual(trail.points.count, 40)
            XCTAssertLessThan(simd_distance(trail.points.last ?? .zero, plan.position(ofWorld: index, at: t)), 1e-9)
        }
    }

    /// The room's dimming takes over while the night is still nearly whole,
    /// so the room never brightens and darkens again on the way out.
    func testTheShellTakesOverUnderTheNight() {
        XCTAssertGreaterThan(plan.nightOpacity(at: OpeningPlan.handOver), 0.8)
        XCTAssertEqual(plan.nightOpacity(at: OpeningPlan.duration), 0, accuracy: 1e-12)
        var previous = 0.0
        for t in stride(from: 0.0, through: OpeningPlan.nightFadeStart, by: frame) {
            XCTAssertGreaterThanOrEqual(plan.nightOpacity(at: t), previous - 1e-12)
            previous = plan.nightOpacity(at: t)
        }
    }
}
