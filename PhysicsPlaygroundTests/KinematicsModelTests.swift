//
//  KinematicsModelTests.swift
//  Kinematics app state; trajectory math is covered in PhysicsCore's ProjectileMotionTests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class KinematicsModelTests: XCTestCase {

    /// A model with the welcome scene swept away, for tests that reason about exact counts.
    private func bareModel() -> KinematicsModel {
        let model = KinematicsModel()
        model.clearFlights()
        while !model.rings.isEmpty { model.removeLastRing() }
        // Neutralise the always-on room; wall tests set their own walls and bounds.
        model.roomWalls = []
        model.roomBounds = RoomBox(center: SIMD3(0, 50, 0),
                                   halfExtents: SIMD3(100, 50, 100))
        return model
    }

    func testFireLaunchesFromMuzzleWithAimAndSpeed() {
        let model = bareModel()
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

    /// A synthetic straight-line hand motion must release the ball with exactly that velocity.
    func testThrowVelocityEstimatedFromHandMotion() {
        let model = bareModel()
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
        let model = bareModel()
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

    /// A well-spawned ball is born AT THE HAND, staged and inert until thrown.
    func testAWellSpawnedBallIsBornAtTheHandAndHangsStill() {
        let model = bareModel()
        let hand = SIMD3<Double>(0.4, 1.3, -0.7)

        let id = model.spawnBall(at: hand)
        let flight = model.flights.first { $0.id == id }
        XCTAssertEqual(flight?.status, .staged)
        XCTAssertEqual(flight?.state.position, hand,
                       "the ball was not born at the fingertips")
        XCTAssertEqual(flight?.projectile.name, model.projectile.name)

        for _ in 0..<180 { model.step(dt: 1.0 / 90.0) }
        XCTAssertEqual(model.flights.first { $0.id == id }?.state.position,
                       hand,
                       "a staged ball moved with nobody touching it")
    }

    /// A stationary release leaves the ball staged — no hand motion, no throw.
    func testStillReleaseLeavesBallHovering() {
        let model = bareModel()
        model.spawnBall()
        let id = model.flights[0].id
        model.grabBall(id: id)
        model.holdBall(id: id, at: SIMD3(0, 1.5, -1))
        model.releaseBall(id: id)
        XCTAssertEqual(model.flights[0].status, .staged)
    }

    /// A fired basketball must land, bounce (e = 0.82), and eventually rest.
    func testFlightBouncesThenComesToRest() {
        let model = bareModel()
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

    /// At hand-throw speeds and real frame times a ball never ends a frame past a wall —
    /// the safety box is parked far away so a tunnel is caught, not silently clamped.
    func testFastFlightsNeverEndAFramePastAWall() {
        for speed in [4.0, 8.0, 12.0] {
            for dt in [1.0 / 90.0, 1.0 / 30.0] {
                let model = bareModel()
                let wallX = 2.0
                model.roomWalls = [RoomWalls.Wall(
                    center: SIMD3(wallX, 1.5, 0), normal: SIMD3(-1, 0, 0),
                    uAxis: SIMD3(0, 0, 1), vAxis: SIMD3(0, 1, 0),
                    halfU: 50, halfV: 50)]
                model.launchSpeed = speed
                model.setAim(elevationDegrees: 10, azimuthDegrees: 0)
                model.fire()

                let radius = model.flights[0].projectile.diameter / 2
                var reach = -Double.infinity
                for _ in 0..<Int(6.0 / dt) where model.flights[0].status == .flying {
                    model.step(dt: dt)
                    reach = max(reach, model.flights[0].state.position.x)
                    XCTAssertLessThanOrEqual(
                        model.flights[0].state.position.x, wallX - radius + 1e-6,
                        "\(speed) m/s at dt \(dt): a frame ended past the wall")
                }
                // The invariant means nothing if the ball never reached the wall.
                XCTAssertGreaterThan(reach, wallX - radius - 0.3,
                                     "\(speed) m/s at dt \(dt): never reached the wall")
            }
        }
    }

    // MARK: Hoops from a well (2026-09-01)

    /// The well's spawn: a hoop is born where the hand is, anchor and
    /// position alike, and no lower than a hoop can be placed.
    func testAHoopIsBornWhereTheHandIs() throws {
        let model = bareModel()
        let hand = SIMD3<Double>(0.4, 1.3, -1.1)
        let id = try XCTUnwrap(model.addRing(at: hand))
        let ring = try XCTUnwrap(model.rings.first { $0.id == id })
        XCTAssertEqual(ring.position, hand)
        XCTAssertEqual(ring.anchor, hand)

        let low = try XCTUnwrap(model.addRing(at: SIMD3(0, 0.05, -1)))
        XCTAssertEqual(model.rings.first { $0.id == low }?.position.y, 0.3,
                       "the floor `moveRing` keeps applies at birth too")
    }

    /// Nil at the budget — the well's cue to fade in refusal.
    func testTheHoopWellRefusesAtTheBudget() {
        let model = bareModel()
        for index in 0..<KinematicsModel.ringBudget {
            XCTAssertNotNil(model.addRing(at: SIMD3(Double(index), 1, -1)))
        }
        XCTAssertNil(model.addRing(at: SIMD3(0, 1, -1)))
        XCTAssertEqual(model.rings.count, KinematicsModel.ringBudget)
    }

    /// The Delete petal takes only its own hoop, and Reset takes them all.
    func testRemoveRingTakesOnlyThatHoopAndResetTakesAll() throws {
        let model = bareModel()
        let first = try XCTUnwrap(model.addRing(at: SIMD3(0, 1, -1)))
        let second = try XCTUnwrap(model.addRing(at: SIMD3(1, 1, -1)))
        model.removeRing(id: first)
        XCTAssertEqual(model.rings.map(\.id), [second])
        model.reset()
        XCTAssertTrue(model.rings.isEmpty)
    }

    // MARK: The aim solves for a hoop (2026-09-01)

    private func fireUntilLanded(_ model: KinematicsModel) {
        model.fire()
        for _ in 0..<3000 where model.flights[0].status == .flying {
            model.step(dt: 1.0 / 90.0)
        }
    }

    /// The criterion the feature rests on: aim at either solution and
    /// the ball goes through the rim. Checked by the scoring law itself,
    /// not by comparing angles to angles.
    func testTheAimSolvesForAHoopAndBothArcsGoThroughIt() throws {
        for pick in [KinematicsModel.AimSolution.low, .high] {
            let model = bareModel()
            model.launchSpeed = 6
            let hoop = model.launcherPosition + SIMD3(2.0, 0.4, -0.8)
            let id = try XCTUnwrap(model.addRing(at: hoop))
            let roots = try XCTUnwrap(model.solutions(for: id))
            XCTAssertLessThan(roots.low, roots.high)

            model.aim(atSolution: pick, for: id)
            fireUntilLanded(model)
            XCTAssertEqual(model.rings[0].score, 1,
                           "the \(pick) solution must put the ball through the rim")
        }
    }

    /// With the air on the roots are found rather than derived, and they
    /// still have to put a table-tennis ball — the draggiest thing on the
    /// bench — through the rim.
    func testTheDragSolveStillPutsTheBallThroughTheRim() throws {
        let model = bareModel()
        model.kind = .tableTennisBall
        model.airResistance = true
        model.launchSpeed = 8
        let id = try XCTUnwrap(model.addRing(at: model.launcherPosition + SIMD3(2.0, 0.3, 0)))
        model.aim(atSolution: .low, for: id)
        fireUntilLanded(model)
        XCTAssertEqual(model.rings[0].score, 1)
    }

    func testOutOfRangeHasNoSolutionAndAimingIsANoOp() throws {
        let model = bareModel()
        model.launchSpeed = 2
        let id = try XCTUnwrap(model.addRing(at: model.launcherPosition + SIMD3(10, 0, 0)))
        XCTAssertNil(model.solutions(for: id))
        let before = model.aimDirection
        model.aim(atSolution: .low, for: id)
        XCTAssertEqual(model.aimDirection, before, "nothing to aim at, nothing moves")
    }

    /// The solve is memoised on its inputs; moving the hoop invalidates it.
    func testTheSolveFollowsTheHoop() throws {
        let model = bareModel()
        model.launchSpeed = 6
        let id = try XCTUnwrap(model.addRing(at: model.launcherPosition + SIMD3(2.0, 0.4, 0)))
        let near = try XCTUnwrap(model.solutions(for: id))
        model.moveRing(id: id, to: model.launcherPosition + SIMD3(3.0, 0.4, 0))
        let far = try XCTUnwrap(model.solutions(for: id))
        XCTAssertGreaterThan(far.low, near.low, "a farther hoop needs a higher low arc")
    }

    /// Reset clears the selection with everything else.
    func testResetClearsTheAimTarget() throws {
        let model = bareModel()
        let id = try XCTUnwrap(model.addRing(at: model.launcherPosition + SIMD3(2, 0, 0)))
        model.aimTargetID = id
        model.reset()
        XCTAssertNil(model.aimTargetID)
    }

    // MARK: The custom ball, and the ghost of vacuum (2026-09-01)

    /// Same diameter, different mass: nothing changes without air, and
    /// the heavier ball flies farther with it.
    func testMassChangesTheArcOnlyInAir() {
        func range(mass: Double, air: Bool) -> Double {
            let model = bareModel()
            model.kind = .custom
            model.customMass = mass
            model.airResistance = air
            model.launchSpeed = 6
            return model.prediction.range
        }
        XCTAssertEqual(range(mass: 0.1, air: false), range(mass: 2.0, air: false), accuracy: 1e-9)
        XCTAssertLessThan(range(mass: 0.1, air: true), range(mass: 2.0, air: true))
    }

    func testTheVacuumGhostExistsOnlyInAirAndFliesFarther() throws {
        let model = bareModel()
        model.kind = .tableTennisBall
        model.launchSpeed = 8
        XCTAssertNil(model.vacuumPrediction, "no air, no gap to show")
        model.airResistance = true
        let ghost = try XCTUnwrap(model.vacuumPrediction)
        XCTAssertGreaterThan(ghost.range, model.prediction.range)
    }

    /// One pass through a hoop scores exactly once; a miss scores nothing.
    func testBallThroughHoopScoresOnceAndMissesDoNot() {
        let model = bareModel()
        model.addRing()
        let ringPosition = SIMD3<Double>(0.5, 1.0, -1.0)
        model.moveRing(id: model.rings[0].id, to: ringPosition)

        model.moveLauncher(to: ringPosition + SIMD3(0, 1.0, 0))
        model.setAim(elevationDegrees: -85, azimuthDegrees: 0)
        model.launchSpeed = 1
        model.fire()
        for _ in 0..<3000 where model.flights[0].status == .flying {
            model.step(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.rings[0].score, 1, "one pass through the hoop = one point")
        XCTAssertEqual(model.totalScore, 1)

        model.clearFlights()
        model.moveLauncher(to: ringPosition + SIMD3(1.0, 1.0, 0))
        model.fire()
        for _ in 0..<3000 where model.flights[0].status == .flying {
            model.step(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.rings[0].score, 1, "a miss must not score")
    }

    /// Slow motion halves simulated progress per wall-time frame.
    func testTimeScaleScalesSimulatedTime() {
        func elapsedAfterSteps(timeScale: Double) -> Double {
            let model = bareModel()
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
        let model = bareModel()
        model.fire()
        model.isPaused = true
        let before = model.flights[0].state
        for _ in 0..<30 {
            model.step(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.flights[0].state, before)
    }

    func testFlightBudgetEvictsSettledFirst() {
        let model = bareModel()
        for _ in 0..<(KinematicsModel.flightBudget + 4) {
            model.fire()
        }
        XCTAssertEqual(model.flights.count, KinematicsModel.flightBudget)
    }

    /// Orbiting hoops circle their anchors at the set radius and snap back when off.
    func testHoopsOrbitMovesRingsAroundAnchors() {
        let model = bareModel()
        model.addRing()
        let anchor = model.rings[0].anchor

        model.hoopsOrbit = true
        for _ in 0..<45 {
            model.step(dt: 1.0 / 90.0)
        }
        let distance = simd_distance(model.rings[0].position, anchor)
        XCTAssertEqual(distance, KinematicsModel.hoopOrbitRadius, accuracy: 1e-9,
                       "an orbiting hoop stays exactly one orbit radius from its anchor")
        XCTAssertEqual(model.rings[0].position.y, anchor.y, accuracy: 1e-9,
                       "hoops orbit in a horizontal circle")

        model.hoopsOrbit = false
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.rings[0].position, anchor)
    }

    /// A score grows the streak (and best); a landed miss with hoops up resets it.
    func testStreakGrowsOnScoresAndDiesOnMisses() {
        UserDefaults.standard.removeObject(forKey: "kinematics.bestStreak")
        let model = bareModel()
        model.addRing()
        let ringPosition = SIMD3<Double>(0.5, 1.0, -1.0)
        model.moveRing(id: model.rings[0].id, to: ringPosition)

        func fire(over target: SIMD3<Double>) {
            model.clearFlights()
            model.moveLauncher(to: target + SIMD3(0, 1.0, 0))
            model.setAim(elevationDegrees: -85, azimuthDegrees: 0)
            model.launchSpeed = 1
            model.fire()
            for _ in 0..<3000 where model.flights.first?.status == .flying {
                model.step(dt: 1.0 / 90.0)
            }
        }

        fire(over: ringPosition)                      // swish
        XCTAssertEqual(model.streak, 1)
        fire(over: ringPosition)                      // swish again
        XCTAssertEqual(model.streak, 2)
        XCTAssertEqual(model.bestStreak, 2)
        fire(over: ringPosition + SIMD3(1, 0, 0))     // air ball
        XCTAssertEqual(model.streak, 0, "a landed miss with hoops up kills the streak")
        XCTAssertEqual(model.bestStreak, 2, "the best survives")
    }

    /// Containment: with room bounds set, no ball ever ends a frame outside the
    /// room — flying, bouncing, or ROLLING — whatever the wall list is doing.
    func testBallNeverEndsAFrameOutsideTheRoom() {
        let model = bareModel()
        let box = RoomBox(center: SIMD3(0, 1.5, -1), halfExtents: SIMD3(2, 1.5, 2))
        model.roomBounds = box
        // No wall rects at all — the worst case, and what anchor churn can produce mid-flight.
        model.roomWalls = []
        model.launchSpeed = 15
        model.setAim(elevationDegrees: 15, azimuthDegrees: 0)
        model.fire()
        model.spawnBall()

        for _ in 0..<1800 {
            model.step(dt: 1.0 / 90.0)
            for flight in model.flights {
                let position = flight.state.position
                let slack = 1e-6
                XCTAssertLessThanOrEqual(abs(position.x - box.center.x),
                                         box.halfExtents.x + slack)
                XCTAssertLessThanOrEqual(position.y - box.center.y,
                                         box.halfExtents.y + slack)
                XCTAssertLessThanOrEqual(abs(position.z - box.center.z),
                                         box.halfExtents.z + slack)
            }
        }
    }

    /// A rolling ball meets a wall and stays inside.
    func testRollingBallRespectsWalls() {
        let model = bareModel()
        model.roomWalls = [RoomWalls.Wall(
            center: SIMD3(1.0, 1.0, -1.0), normal: SIMD3(1, 0, 0),
            uAxis: SIMD3(0, 0, 1), vAxis: SIMD3(0, 1, 0),
            halfU: 3, halfV: 1.5)]
        model.roomBounds = RoomBox(center: SIMD3(0, 1.5, -1),
                                   halfExtents: SIMD3(1.0, 1.5, 3))
        model.launchSpeed = 6
        model.setAim(elevationDegrees: 5, azimuthDegrees: 0)
        model.fire()

        for _ in 0..<2700 {
            model.step(dt: 1.0 / 90.0)
            for flight in model.flights {
                XCTAssertLessThanOrEqual(flight.state.position.x, 1.0 + 1e-6,
                                         "no phase of the flight passes the wall")
            }
        }
    }

    func testFirePublishesSoundEvent() {
        // The welcome scene fires once in init — what matters is that OUR fire publishes a fresh event.
        let model = bareModel()
        let before = model.soundEvent?.id
        model.fire()
        let event = try! XCTUnwrap(model.soundEvent)
        XCTAssertNotEqual(event.id, before)
        XCTAssertEqual(event.kind, .pop)
        XCTAssertEqual(simd_distance(event.position, model.muzzlePoint), 0, accuracy: 1e-9)
    }

    /// Wind only blows through air: with `airResistance` off, a leftover wind speed
    /// must do nothing at all, or the hidden rail hides a force still bending trajectories.
    func testWindDoesNothingWithoutAirResistance() {
        func landing(air: Bool, wind: Double) -> SIMD3<Double> {
            let model = bareModel()
            model.airResistance = air
            model.windSpeed = wind
            model.fire()
            for _ in 0..<400 { model.step(dt: 1.0 / 90.0) }
            return model.flights[0].state.position
        }
        XCTAssertEqual(
            simd_distance(landing(air: false, wind: 0),
                          landing(air: false, wind: 12)),
            0, accuracy: 1e-12, "wind blew a ball through vacuum")
        XCTAssertGreaterThan(
            simd_distance(landing(air: true, wind: 0),
                          landing(air: true, wind: 12)),
            0.05, "12 m/s of wind moved the ball less than 5 cm")
    }

    /// The worlds bank lights whichever world's g you are on, by this exact comparison.
    func testTheWorldBankLightsTheMatchingDisc() {
        let model = bareModel()
        func lit() -> String? {
            KinematicsModel.gravityPresets
                .first { abs($0.gravity - model.gravity) < 0.01 }?.name
        }
        XCTAssertEqual(lit(), "Earth")
        for world in KinematicsModel.gravityPresets {
            model.gravity = world.gravity
            XCTAssertEqual(lit(), world.name)
            XCTAssertTrue(KinematicsModel.gravityRange.contains(world.gravity),
                          "\(world.name) is off the rail the discs share")
        }
        model.gravity = 5.0
        XCTAssertNil(lit(), "between worlds, no disc is lit")
    }

    func testResetRestoresFreshlyEnteredState() {
        let model = bareModel()
        model.launchSpeed = 3
        model.gravity = 1.62
        model.airResistance = true
        model.respectRoomWalls = false
        model.windSpeed = 5
        model.timeScale = 0.3
        model.isPaused = true
        model.throwBoost = 2
        model.kind = .golfBall
        model.moveLauncher(to: SIMD3(2, 2, 2))
        model.addRing()
        model.fire()

        model.reset()

        // The opening scene: no hoops, one shot already flying from the muzzle.
        XCTAssertTrue(model.rings.isEmpty, "hoops are retired from the opening scene")
        XCTAssertEqual(model.flights.count, 1)
        XCTAssertTrue(model.flights.contains { $0.status == .flying },
                      "the module is alive the instant it appears")
        XCTAssertEqual(model.totalScore, 0)
        // The default launch must land inside a room: range = v²/g at 45°.
        let range = model.launchSpeed * model.launchSpeed / model.gravity
        XCTAssertLessThan(range, 3.0,
                          "a first shot must not leave through the far wall")
        XCTAssertEqual(model.launchSpeed, KinematicsModel.roomFittingSpeed, accuracy: 1e-12)
        XCTAssertEqual(model.gravity, 9.81)
        XCTAssertFalse(model.airResistance)
        // `respectRoomWalls` once escaped reset() — a flag with no visible control drifts out of reset.
        XCTAssertTrue(model.respectRoomWalls, "the room stopped being real")
        XCTAssertEqual(model.windSpeed, 0)
        XCTAssertEqual(model.timeScale, 1.0)
        XCTAssertFalse(model.isPaused)
        XCTAssertEqual(model.throwBoost, 1.0)
        XCTAssertEqual(model.kind, .golfBall)
        XCTAssertEqual(model.launcherPosition, KinematicsModel.launcherHome)
        XCTAssertEqual(model.elevationDegrees, 45, accuracy: 1e-9)
    }
}
