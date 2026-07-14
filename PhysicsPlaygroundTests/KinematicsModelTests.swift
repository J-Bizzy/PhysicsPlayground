//
//  KinematicsModelTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the room-scale kinematics app state: firing from the
//  launcher, hand-throw velocity estimation, bounce-to-rest lifecycle,
//  hoop scoring, slow motion, budgets, and reset. Trajectory math itself
//  is covered in PhysicsCore's ProjectileMotionTests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class KinematicsModelTests: XCTestCase {

    func testFireLaunchesFromMuzzleWithAimAndSpeed() {
        let model = KinematicsModel()
        model.launchSpeed = 5
        model.setAim(elevationDegrees: 30, azimuthDegrees: 0)
        model.fire()

        XCTAssertEqual(model.flights.count, 1)
        let flight = model.flights[0]
        XCTAssertEqual(flight.status, .flying)
        XCTAssertEqual(simd_distance(flight.state.position, model.muzzlePoint), 0, accuracy: 1e-9)
        XCTAssertEqual(flight.state.velocity.x, 5 * cos(30 * .pi / 180), accuracy: 1e-9)
        XCTAssertEqual(flight.state.velocity.y, 5 * sin(30 * .pi / 180), accuracy: 1e-9)
        XCTAssertFalse(flight.wasThrown)
    }

    /// Feeding the hold pipeline a synthetic straight-line hand motion
    /// must release the ball with exactly that hand velocity.
    func testThrowVelocityEstimatedFromHandMotion() {
        let model = KinematicsModel()
        model.spawnBall()
        let id = model.flights[0].id
        model.grabBall(id: id)

        // 2 m/s along +x with a little upward lift, sampled at 90 Hz.
        let start = SIMD3<Double>(0, 1.2, -0.8)
        let velocity = SIMD3<Double>(2, 0.5, 0)
        for sample in 0..<10 {
            let t = Double(sample) / 90.0
            model.holdBall(id: id, at: start + t * velocity, timestamp: 100.0 + t)
        }
        model.releaseBall(id: id, timestamp: 100.0 + 9.0 / 90.0)

        let flight = model.flights[0]
        XCTAssertEqual(flight.status, .flying)
        XCTAssertTrue(flight.wasThrown)
        XCTAssertEqual(flight.state.velocity.x, 2.0, accuracy: 1e-9)
        XCTAssertEqual(flight.state.velocity.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(flight.state.velocity.z, 0.0, accuracy: 1e-9)
    }

    /// The throw boost multiplies the estimated hand velocity.
    func testThrowBoostAmplifiesRelease() {
        let model = KinematicsModel()
        model.throwBoost = 2.0
        model.spawnBall()
        let id = model.flights[0].id
        model.grabBall(id: id)
        for sample in 0..<10 {
            let t = Double(sample) / 90.0
            model.holdBall(id: id, at: SIMD3(t * 1.0, 1.2, -0.8), timestamp: 200.0 + t)
        }
        model.releaseBall(id: id, timestamp: 200.0 + 9.0 / 90.0)
        XCTAssertEqual(model.flights[0].state.velocity.x, 2.0, accuracy: 1e-9,
                       "1 m/s hand motion × boost 2 = 2 m/s release")
    }

    /// A grabbed-and-stationary release leaves the ball hovering (staged),
    /// not falling — no meaningful hand motion means no throw.
    func testStillReleaseLeavesBallHovering() {
        let model = KinematicsModel()
        model.spawnBall()
        let id = model.flights[0].id
        model.grabBall(id: id)
        model.holdBall(id: id, at: SIMD3(0, 1.5, -1))
        model.releaseBall(id: id)
        XCTAssertEqual(model.flights[0].status, .staged)
    }

    /// A fired basketball must land, bounce (e = 0.82), and eventually rest.
    func testFlightBouncesThenComesToRest() {
        let model = KinematicsModel()
        model.launchSpeed = 4
        model.setAim(elevationDegrees: 45, azimuthDegrees: 0)
        model.fire()

        for _ in 0..<8000 where model.flights[0].status != .rested {
            model.step(dt: 1.0 / 90.0)
        }
        let flight = model.flights[0]
        XCTAssertEqual(flight.status, .rested)
        XCTAssertGreaterThan(flight.bounces, 0, "a basketball must bounce before resting")
        XCTAssertEqual(flight.state.position.y, flight.projectile.diameter / 2, accuracy: 1e-9,
                       "a rested ball sits on the floor")
        let summary = try! XCTUnwrap(model.lastFlight)
        XCTAssertGreaterThan(summary.range, 0.5)
        XCTAssertFalse(summary.wasThrown)
    }

    /// A ball fired down through a hoop scores exactly once; one that
    /// misses the rim scores nothing.
    func testBallThroughHoopScoresOnceAndMissesDoNot() {
        let model = KinematicsModel()
        model.addRing()
        let ringPosition = SIMD3<Double>(0.5, 1.0, -1.0)
        model.moveRing(id: model.rings[0].id, to: ringPosition)

        // Fire straight down from directly above the rim's center.
        model.moveLauncher(to: ringPosition + SIMD3(0, 1.0, 0))
        model.setAim(elevationDegrees: -85, azimuthDegrees: 0)
        model.launchSpeed = 1
        model.fire()
        for _ in 0..<3000 where model.flights[0].status == .flying {
            model.step(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.rings[0].score, 1, "one pass through the hoop = one point")
        XCTAssertEqual(model.totalScore, 1)

        // A drop well to the side must not score.
        model.clearFlights()
        model.moveLauncher(to: ringPosition + SIMD3(1.0, 1.0, 0))
        model.fire()
        for _ in 0..<3000 where model.flights[0].status == .flying {
            model.step(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.rings[0].score, 1, "a miss must not score")
    }

    /// Slow motion halves simulated progress: after the same wall time,
    /// a 0.5× flight has advanced half as far.
    func testTimeScaleScalesSimulatedTime() {
        func elapsedAfterSteps(timeScale: Double) -> Double {
            let model = KinematicsModel()
            model.gravity = 0  // no landing mid-test
            model.launchSpeed = 2
            model.timeScale = timeScale
            model.fire()
            for _ in 0..<90 {
                model.step(dt: 1.0 / 90.0)
            }
            return model.flights[0].elapsed
        }
        XCTAssertEqual(elapsedAfterSteps(timeScale: 1.0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(elapsedAfterSteps(timeScale: 0.5), 0.5, accuracy: 1e-9)
    }

    func testPauseFreezesFlights() {
        let model = KinematicsModel()
        model.fire()
        model.isPaused = true
        let before = model.flights[0].state
        for _ in 0..<30 {
            model.step(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.flights[0].state, before)
    }

    func testFlightBudgetEvictsSettledFirst() {
        let model = KinematicsModel()
        for _ in 0..<(KinematicsModel.flightBudget + 4) {
            model.fire()
        }
        XCTAssertEqual(model.flights.count, KinematicsModel.flightBudget)
    }

    func testResetRestoresFreshlyEnteredState() {
        let model = KinematicsModel()
        model.launchSpeed = 3
        model.gravity = 1.62
        model.airResistance = true
        model.windSpeed = 5
        model.timeScale = 0.3
        model.isPaused = true
        model.throwBoost = 2
        model.kind = .golfBall
        model.moveLauncher(to: SIMD3(2, 2, 2))
        model.addRing()
        model.fire()

        model.reset()

        XCTAssertTrue(model.flights.isEmpty)
        XCTAssertTrue(model.rings.isEmpty)
        XCTAssertNil(model.lastFlight)
        XCTAssertEqual(model.launchSpeed, 6.0)
        XCTAssertEqual(model.gravity, 9.81)
        XCTAssertFalse(model.airResistance)
        XCTAssertEqual(model.windSpeed, 0)
        XCTAssertEqual(model.timeScale, 1.0)
        XCTAssertFalse(model.isPaused)
        XCTAssertEqual(model.throwBoost, 1.0)
        XCTAssertEqual(model.kind, .basketball)
        XCTAssertEqual(model.launcherPosition, KinematicsModel.launcherHome)
        XCTAssertEqual(model.elevationDegrees, 45, accuracy: 1e-9)
    }
}
