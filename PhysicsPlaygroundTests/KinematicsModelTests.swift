//
//  KinematicsModelTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the kinematics app state: firing, aiming clamps, the flight
//  budget, frame-stepped landings against the analytic range, and reset.
//  Trajectory math itself is covered in PhysicsCore's ProjectileMotionTests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class KinematicsModelTests: XCTestCase {

    func testFireUsesCurrentAimAndSpeed() {
        let model = KinematicsModel()
        model.launchSpeed = 5
        model.setAim(elevationDegrees: 30, azimuthDegrees: 0)
        model.fire()

        XCTAssertEqual(model.flights.count, 1)
        let velocity = model.flights[0].state.velocity
        XCTAssertEqual(velocity.x, 5 * cos(30 * .pi / 180), accuracy: 1e-9)
        XCTAssertEqual(velocity.y, 5 * sin(30 * .pi / 180), accuracy: 1e-9)
        XCTAssertEqual(velocity.z, 0, accuracy: 1e-9)
    }

    func testFlightBudgetIsEnforced() {
        let model = KinematicsModel()
        for _ in 0..<(KinematicsModel.flightBudget + 5) {
            model.fire()
        }
        XCTAssertEqual(model.flights.count, KinematicsModel.flightBudget)
    }

    func testAimClampsElevationAndAzimuth() {
        let model = KinematicsModel()
        // Nearly straight up → clamped to the max elevation.
        model.aim(toward: SIMD3(0.1, 10, 0))
        XCTAssertLessThanOrEqual(model.elevationDegrees,
                                 KinematicsModel.elevationRangeDegrees.upperBound + 1e-9)
        // Hard sideways → azimuth clamped.
        model.aim(toward: SIMD3(1, 0.5, 10))
        XCTAssertLessThanOrEqual(abs(model.azimuthDegrees),
                                 KinematicsModel.maxAzimuthDegrees + 1e-9)
    }

    /// Frame-stepped flight (like the app runs) must land at the analytic
    /// drag-free range — the landing interpolation keeps it tight.
    func testFrameSteppedLandingMatchesAnalyticRange() {
        let model = KinematicsModel()
        model.launchSpeed = 7
        model.setAim(elevationDegrees: 45, azimuthDegrees: 0)
        model.airResistance = false
        model.fire()

        for _ in 0..<2000 where model.flights[0].status == .flying {
            model.step(dt: 1.0 / 90.0)
        }

        XCTAssertEqual(model.flights[0].status, .landed)
        let expected = ProjectileMotion.dragFreeRange(speed: 7, angle: .pi / 4, gravity: 9.81)
        let last = try! XCTUnwrap(model.lastFlight)
        XCTAssertEqual(last.range, expected, accuracy: expected * 0.005)
        XCTAssertEqual(last.apexHeight,
                       ProjectileMotion.dragFreeApex(speed: 7, angle: .pi / 4, gravity: 9.81),
                       accuracy: 0.01)
        XCTAssertFalse(last.wentOffTable)
        XCTAssertFalse(model.flights[0].dots.isEmpty, "a landed flight leaves strobe dots")
    }

    func testHardLunarThrowGoesOffTheTable() {
        let model = KinematicsModel()
        model.launchSpeed = 10
        model.gravity = 1.62
        model.setAim(elevationDegrees: 45, azimuthDegrees: 0)
        model.fire()

        for _ in 0..<5000 where model.flights[0].status == .flying {
            model.step(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.flights[0].status, .offTable)
        XCTAssertEqual(model.lastFlight?.wentOffTable, true)
    }

    func testResetRestoresFreshlyEnteredState() {
        let model = KinematicsModel()
        model.launchSpeed = 3
        model.gravity = 1.62
        model.airResistance = true
        model.kind = .golfBall
        model.setAim(elevationDegrees: 20, azimuthDegrees: 15)
        model.fire()

        model.reset()

        XCTAssertTrue(model.flights.isEmpty)
        XCTAssertNil(model.lastFlight)
        XCTAssertEqual(model.launchSpeed, 7.0)
        XCTAssertEqual(model.gravity, 9.81)
        XCTAssertFalse(model.airResistance)
        XCTAssertEqual(model.kind, .basketball)
        XCTAssertEqual(model.elevationDegrees, 45, accuracy: 1e-9)
        XCTAssertEqual(model.azimuthDegrees, 0, accuracy: 1e-9)
    }
}
