//  BobCollisionTests.swift
//  Cradle behaviour must emerge from pairwise resolution — nothing in BobCollision counts balls.

import XCTest
@testable import PhysicsCore

final class BobCollisionTests: XCTestCase {

    private func cradle(count: Int = 5, radius: Double = 0.02,
                        firstVelocity: Double = 0) -> [BobCollision.Bob] {
        (0..<count).map { index in
            BobCollision.Bob(position: Double(index) * radius * 2,
                             velocity: index == 0 ? firstVelocity : 0,
                             mass: 0.05, radius: radius)
        }
    }

    // MARK: The headline

    /// One ball in, ONE out at the same speed: sequential pairwise contacts pick the
    /// physical answer a simultaneous conserving 5-body solve underdetermines.
    func testOneBallInSendsExactlyOneBallOut() {
        var bobs = cradle(firstVelocity: 1.0)
        BobCollision.resolve(&bobs)

        XCTAssertEqual(bobs[4].velocity, 1.0, accuracy: 1e-12,
                       "the far ball should leave at the speed the near one arrived")
        for index in 0..<4 {
            XCTAssertEqual(bobs[index].velocity, 0, accuracy: 1e-12,
                           "ball \(index) should have been left at rest")
        }
    }

    /// TWO balls in, two balls out. The same sweep, no extra rule.
    func testTwoBallsInSendTwoBallsOut() {
        var bobs = cradle()
        bobs[0].velocity = 1.0
        bobs[1].velocity = 1.0
        BobCollision.resolve(&bobs)

        XCTAssertEqual(bobs[3].velocity, 1.0, accuracy: 1e-12)
        XCTAssertEqual(bobs[4].velocity, 1.0, accuracy: 1e-12)
        for index in 0..<3 {
            XCTAssertEqual(bobs[index].velocity, 0, accuracy: 1e-12)
        }
    }

    // MARK: Conservation

    /// Momentum and energy both survive, for any number of contacts.
    func testAnElasticSweepConservesMomentumAndEnergy() {
        var bobs = cradle(count: 6, firstVelocity: 1.4)
        bobs[5].velocity = -0.6          // and one coming back the other way
        let momentum = BobCollision.momentum(bobs)
        let energy = BobCollision.kineticEnergy(bobs)

        BobCollision.resolve(&bobs)

        XCTAssertEqual(BobCollision.momentum(bobs), momentum, accuracy: 1e-12)
        XCTAssertEqual(BobCollision.kineticEnergy(bobs), energy, accuracy: 1e-12)
    }

    /// Equal masses swap velocities exactly — the identity the cradle is built on.
    func testEqualMassesSwapVelocities() {
        let (a, b) = BobCollision.exchange((velocity: 2.5, mass: 0.05),
                                           (velocity: -1.0, mass: 0.05))
        XCTAssertEqual(a, -1.0, accuracy: 1e-12)
        XCTAssertEqual(b, 2.5, accuracy: 1e-12)
    }

    /// Light-off-heavy limit: light rebounds at nearly its own speed, heavy barely moves.
    func testALightBallReboundsOffAHeavyOne() {
        let (light, heavy) = BobCollision.exchange((velocity: 1.0, mass: 0.001),
                                                    (velocity: 0.0, mass: 1000))
        XCTAssertEqual(light, -1.0, accuracy: 1e-4)
        XCTAssertEqual(heavy, 0.0, accuracy: 1e-5)
    }

    /// Restitution < 1 sheds energy but must still conserve momentum exactly.
    func testInelasticCollisionsStillConserveMomentum() {
        for restitution in [0.0, 0.35, 0.8] {
            var bobs = cradle(firstVelocity: 1.0)
            let momentum = BobCollision.momentum(bobs)
            let energy = BobCollision.kineticEnergy(bobs)

            BobCollision.resolve(&bobs, restitution: restitution)

            XCTAssertEqual(BobCollision.momentum(bobs), momentum, accuracy: 1e-12,
                           "momentum lost at restitution \(restitution)")
            XCTAssertLessThanOrEqual(BobCollision.kineticEnergy(bobs),
                                     energy + 1e-12,
                                     "energy GAINED at restitution \(restitution)")
        }
    }

    // MARK: The guards

    /// An overlapping-but-separating pair must not be re-resolved — re-resolving
    /// is how a cradle jitters and gains energy over the post-hit contact frames.
    func testAlreadySeparatingBallsAreLeftAlone() {
        var bobs = [
            BobCollision.Bob(position: 0, velocity: -0.4, mass: 0.05, radius: 0.02),
            BobCollision.Bob(position: 0.03, velocity: 0.4, mass: 0.05, radius: 0.02),
        ]
        let before = bobs
        let contacts = BobCollision.resolve(&bobs)
        XCTAssertEqual(contacts, 0, "a separating pair was collided again")
        XCTAssertEqual(bobs, before)
    }

    func testBallsOutOfContactDoNothing() {
        var bobs = [
            BobCollision.Bob(position: 0, velocity: 1.0, mass: 0.05, radius: 0.02),
            BobCollision.Bob(position: 0.5, velocity: 0, mass: 0.05, radius: 0.02),
        ]
        XCTAssertEqual(BobCollision.resolve(&bobs), 0)
        XCTAssertEqual(bobs[0].velocity, 1.0)
    }

    func testASingleBallAndAnEmptyLineAreNoOps() {
        var one = [BobCollision.Bob(position: 0, velocity: 1,
                                    mass: 0.05, radius: 0.02)]
        XCTAssertEqual(BobCollision.resolve(&one), 0)
        var none: [BobCollision.Bob] = []
        XCTAssertEqual(BobCollision.resolve(&none), 0)
    }

    func testResolutionTerminatesOnAFullyOverlappingPile() {
        var bobs = (0..<8).map { index in
            BobCollision.Bob(position: Double(index) * 0.001,
                             velocity: Double(8 - index),
                             mass: 0.05, radius: 0.02)
        }
        XCTAssertNoThrow(BobCollision.resolve(&bobs))
        for bob in bobs {
            XCTAssertFalse(bob.velocity.isNaN)
        }
    }
}
