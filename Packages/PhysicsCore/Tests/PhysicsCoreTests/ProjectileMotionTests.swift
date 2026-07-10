//
//  ProjectileMotionTests.swift
//  PhysicsCoreTests
//
//  The drag-free closed forms and the RK4 simulation check each other:
//  with drag off they must agree to high precision. Drag behavior is
//  pinned by physics facts — drag shortens flights, dropped objects
//  approach terminal velocity, and the range-optimal angle drops below
//  45° once air pushes back.
//

import XCTest
import simd
@testable import PhysicsCore

final class ProjectileMotionTests: XCTestCase {

    private func launchVelocity(speed: Double, angleDegrees: Double) -> SIMD3<Double> {
        let angle = angleDegrees * .pi / 180
        return SIMD3(speed * cos(angle), speed * sin(angle), 0)
    }

    // MARK: Drag-free: simulation vs closed forms

    func testVacuumSimulationMatchesClosedForms() {
        let speed = 7.0, angleDegrees = 40.0, g = 9.81
        let angle = angleDegrees * .pi / 180
        let trajectory = ProjectileMotion.simulate(
            launchVelocity: launchVelocity(speed: speed, angleDegrees: angleDegrees),
            gravity: g
        )

        let range = ProjectileMotion.dragFreeRange(speed: speed, angle: angle, gravity: g)
        let apex = ProjectileMotion.dragFreeApex(speed: speed, angle: angle, gravity: g)
        let time = ProjectileMotion.dragFreeFlightTime(speed: speed, angle: angle, gravity: g)

        XCTAssertTrue(trajectory.landed)
        XCTAssertEqual(trajectory.range, range, accuracy: range * 1e-3)
        XCTAssertEqual(trajectory.apexHeight, apex, accuracy: apex * 1e-3)
        XCTAssertEqual(trajectory.flightTime, time, accuracy: time * 1e-3)
    }

    /// 45° maximizes drag-free range (checked against neighbors).
    func testVacuumOptimalAngleIs45() {
        let g = 9.81
        let at45 = ProjectileMotion.dragFreeRange(speed: 10, angle: .pi / 4, gravity: g)
        for degrees in [30.0, 40.0, 50.0, 60.0] {
            let range = ProjectileMotion.dragFreeRange(speed: 10, angle: degrees * .pi / 180, gravity: g)
            XCTAssertLessThan(range, at45)
        }
    }

    /// Range is horizontal distance, so aiming off-axis must not change it.
    func testRangeIsAzimuthIndependent() {
        let g = 9.81
        let straight = ProjectileMotion.simulate(
            launchVelocity: SIMD3(7 * cos(0.6), 7 * sin(0.6), 0), gravity: g)
        let angled = ProjectileMotion.simulate(
            launchVelocity: SIMD3(7 * cos(0.6) * 0.8, 7 * sin(0.6), 7 * cos(0.6) * 0.6), gravity: g)
        XCTAssertEqual(straight.range, angled.range, accuracy: straight.range * 1e-6)
    }

    // MARK: Drag physics

    func testDragShortensRangeAndLowersApex() {
        let g = 9.81
        let v = launchVelocity(speed: 10, angleDegrees: 45)
        let vacuum = ProjectileMotion.simulate(launchVelocity: v, gravity: g)
        let air = ProjectileMotion.simulate(
            launchVelocity: v, gravity: g,
            drag: ProjectileMotion.Drag(projectile: .basketball)
        )
        XCTAssertLessThan(air.range, vacuum.range * 0.95,
                          "a basketball at 10 m/s must lose noticeably to drag")
        XCTAssertLessThan(air.apexHeight, vacuum.apexHeight)
        XCTAssertLessThan(air.flightTime, vacuum.flightTime)
    }

    /// A dropped table-tennis ball reaches √(2mg/ρCdA) ≈ 9 m/s and stays.
    func testDroppedBallApproachesTerminalSpeed() {
        let g = 9.81
        let drag = ProjectileMotion.Drag(projectile: .tableTennisBall)
        let terminal = ProjectileMotion.terminalSpeed(projectile: .tableTennisBall, gravity: g)

        // Integrate a free fall directly (no ground plane in the way).
        var state = ParticleDynamics.State(position: .zero, velocity: .zero)
        let dt = 1.0 / 240.0
        for _ in 0..<Int(8.0 / dt) {
            state = Integrators.rk4Step(state, dt: dt) { _, v in
                ProjectileMotion.acceleration(velocity: v, gravity: g, drag: drag)
            }
        }
        let speed = simd_length(state.velocity)
        XCTAssertEqual(speed, terminal, accuracy: terminal * 0.01,
                       "after 8 s a table-tennis ball is within 1% of terminal speed")
        XCTAssertLessThanOrEqual(speed, terminal * 1.001,
                                 "falling from rest can never exceed terminal speed")
    }

    /// With drag on, the range-optimal launch angle drops below 45°.
    func testDragOptimalAngleIsBelow45() {
        let g = 9.81
        let drag = ProjectileMotion.Drag(projectile: .basketball)

        func range(atDegrees degrees: Double) -> Double {
            ProjectileMotion.simulate(
                launchVelocity: launchVelocity(speed: 10, angleDegrees: degrees),
                gravity: g, drag: drag
            ).range
        }

        var bestAngle = 0.0
        var bestRange = 0.0
        for degrees in stride(from: 30.0, through: 50.0, by: 1.0) {
            let r = range(atDegrees: degrees)
            if r > bestRange {
                bestRange = r
                bestAngle = degrees
            }
        }
        XCTAssertLessThan(bestAngle, 45,
                          "air resistance must pull the optimal angle below 45°; got \(bestAngle)°")
    }

    /// Weaker gravity means longer flights — and unlanded trajectories
    /// (lunar hard throw) must report landed = false, not lie.
    func testLowGravityFliesFartherAndHonestlyReportsNoLanding() {
        let v = launchVelocity(speed: 10, angleDegrees: 45)
        let earth = ProjectileMotion.simulate(launchVelocity: v, gravity: 9.81)
        let moon = ProjectileMotion.simulate(launchVelocity: v, gravity: 1.62)
        XCTAssertGreaterThan(moon.range, earth.range * 5)

        let capped = ProjectileMotion.simulate(launchVelocity: v, gravity: 1.62, maxDuration: 0.5)
        XCTAssertFalse(capped.landed)
    }
}
