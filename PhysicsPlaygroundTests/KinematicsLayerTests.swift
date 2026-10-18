//
//  KinematicsLayerTests.swift
//  PhysicsPlaygroundTests
//
//  Projectiles made minimal (2026-10-17): the room is the launcher, its
//  bead and the balls. The predicted arc with its apex and landing marks
//  is the Trajectory layer and every number is the Numbers layer, both in
//  More and both off until asked for — except that the bead shows its own
//  reading while a hand holds it, and a hoop being aimed at still shows the
//  arcs that reach it. The strobe keeps only the newest landed flight.
//

import XCTest
import PhysicsCore
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class KinematicsLayerTests: XCTestCase {

    private func enabled(_ name: String, in renderer: KinematicsRenderer,
                         file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let entity = renderer.root.findEntity(named: name) else {
            XCTFail("no entity named \(name)", file: file, line: line)
            return false
        }
        return entity.isEnabled
    }

    func testTheRoomOpensWithNoPredictionAndNoNumbers() {
        let model = KinematicsModel()
        XCTAssertFalse(model.showsTrajectory)
        XCTAssertFalse(model.showsNumbers)
        let renderer = KinematicsRenderer()
        renderer.tick(model)
        for name in ["predicted-arc", "apex-marker", "landing-marker", "bead-reading"] {
            XCTAssertFalse(enabled(name, in: renderer), "\(name) shows in the quiet room")
        }
    }

    func testTheTrajectoryShowsTheArcAndItsMarks() {
        let model = KinematicsModel()
        model.showsTrajectory = true
        let renderer = KinematicsRenderer()
        renderer.tick(model)
        XCTAssertTrue(enabled("predicted-arc", in: renderer))
        XCTAssertTrue(enabled("apex-marker", in: renderer))
        XCTAssertTrue(enabled("landing-marker", in: renderer))
        XCTAssertFalse(enabled("bead-reading", in: renderer), "the Numbers are a separate layer")
        model.showsTrajectory = false
        renderer.tick(model)
        XCTAssertFalse(enabled("predicted-arc", in: renderer))
        XCTAssertFalse(enabled("landing-marker", in: renderer))
    }

    func testTheNumbersShowTheBeadReading() {
        let model = KinematicsModel()
        model.showsNumbers = true
        let renderer = KinematicsRenderer()
        renderer.tick(model)
        XCTAssertTrue(enabled("bead-reading", in: renderer))
        XCTAssertFalse(enabled("predicted-arc", in: renderer))
    }

    /// A handle shows its value while you handle it.
    func testAHeldBeadShowsItsReadingWithTheNumbersOff() {
        let model = KinematicsModel()
        let renderer = KinematicsRenderer()
        renderer.beadHeld = true
        renderer.tick(model)
        XCTAssertTrue(enabled("bead-reading", in: renderer))
        renderer.beadHeld = false
        renderer.tick(model)
        XCTAssertFalse(enabled("bead-reading", in: renderer))
    }

    /// The launcher and a throw read the same way.
    func testTheBeadAndAThrowReadAlike() {
        let release = KinematicsModel.Flight.Release(
            position: .zero, velocity: 6 * SIMD3(cos(.pi / 4), sin(.pi / 4), 0))
        XCTAssertEqual(KinematicsRenderer.releaseText(release),
                       KinematicsRenderer.launchText(elevationDegrees: 45, speed: 6))
        XCTAssertTrue(KinematicsRenderer.launchText(elevationDegrees: 45, speed: 6)
            .hasPrefix("45° · "))
    }

    /// Aiming at a hoop is a request for the arcs that reach it, so they show
    /// with the Trajectory off; the vacuum ghost is part of the Trajectory.
    func testTheHoopsArcsShowAndTheVacuumGhostWaitsForTheTrajectory() throws {
        let model = KinematicsModel()
        model.airResistance = true
        let renderer = KinematicsRenderer()
        renderer.tick(model)
        XCTAssertFalse(enabled("ghost-arcs", in: renderer), "the vacuum ghost showed on its own")
        model.showsTrajectory = true
        renderer.tick(model)
        XCTAssertTrue(enabled("ghost-arcs", in: renderer))

        model.showsTrajectory = false
        model.airResistance = false
        let hoop = try XCTUnwrap(model.addRing(at: model.launcherPosition + SIMD3(1.2, 0.3, 0)))
        model.aimTargetID = hoop
        XCTAssertNotNil(model.solutions(for: hoop))
        renderer.tick(model)
        XCTAssertTrue(enabled("ghost-arcs", in: renderer), "the arcs to a hoop being aimed at hid")
    }

    // MARK: The strobe

    private func flight(_ status: KinematicsModel.Flight.Status, serial: Int,
                        dots: Int = 5) -> KinematicsModel.Flight {
        var flight = KinematicsModel.Flight(id: UUID(), projectile: .golfBall,
                                            state: ParticleDynamics.State(position: .zero))
        flight.status = status
        flight.launchSerial = serial
        flight.dots = Array(repeating: .zero, count: dots)
        return flight
    }

    func testOnlyTheNewestLandedFlightKeepsItsDots() {
        let older = flight(.rested, serial: 1)
        let newer = flight(.rested, serial: 2)
        // Listed newest first: the strobe goes by launch, not by slot.
        XCTAssertEqual(KinematicsRenderer.flightsKeepingDots([newer, older]), [newer.id])
    }

    func testABallStillInTheAirKeepsItsDotsWhateverItsAge() {
        let flying = flight(.flying, serial: 1)
        let rolling = flight(.rolling, serial: 2)
        let landed = flight(.rested, serial: 3)
        XCTAssertEqual(KinematicsRenderer.flightsKeepingDots([flying, rolling, landed]),
                       [flying.id, rolling.id, landed.id])
    }

    func testABallInHandHasNoDotsToKeep() {
        let held = flight(.held, serial: 4, dots: 0)
        let landed = flight(.rested, serial: 3)
        XCTAssertEqual(KinematicsRenderer.flightsKeepingDots([held, landed]), [landed.id])
    }

    /// Each launch gets the next serial, a rethrow included.
    func testLaunchesCountUpInTheOrderTheyLeave() throws {
        let model = KinematicsModel()
        model.fire()
        model.fire()
        let serials = model.flights.map(\.launchSerial)
        XCTAssertEqual(serials.count, 2)
        XCTAssertLessThan(serials[0], serials[1])
    }

    func testTheLayersAreToggledFromMore() {
        let model = KinematicsModel()
        let items = KinematicsModule.more(model)
        for (id, flag) in [("trajectory", \KinematicsModel.showsTrajectory),
                           ("numbers", \KinematicsModel.showsNumbers)] {
            guard let item = items.first(where: { $0.id == id }),
                  case let .toggle(_, _, _, isOn, set, _) = item else {
                XCTFail("More has no \(id) toggle")
                continue
            }
            XCTAssertFalse(isOn())
            set(true)
            XCTAssertTrue(model[keyPath: flag])
        }
    }
}
