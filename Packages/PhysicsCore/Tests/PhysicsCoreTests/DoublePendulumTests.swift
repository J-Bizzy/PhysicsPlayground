//
//  DoublePendulumTests.swift
//  PhysicsCoreTests
//
//  Chaos defeats trajectory-pinning, so these check what chaos does not touch:
//  energy conservation, analytic normal modes, degenerate limits.
//

import XCTest
import simd
@testable import PhysicsCore

final class DoublePendulumTests: XCTestCase {

    private let rig = DoublePendulum.Rig(length1: 0.5, length2: 0.5,
                                         mass1: 1.0, mass2: 1.0)
    private let g = 9.81

    // MARK: Energy

    /// Undamped energy conservation through a chaotic start — catches any
    /// non-Lagrangian error; RK4 at 1/240 s holds well under 0.1% over 20 s.
    func testEnergyIsConservedThroughChaoticMotion() {
        var state = DoublePendulum(theta1: 1.6, theta2: 1.5)
        let initial = state.energy(rig: rig, gravity: g)
        let dt = 1.0 / 240
        for _ in 0..<(240 * 20) {
            state = DoublePendulum.step(state, dt: dt, rig: rig, gravity: g)
        }
        let final = state.energy(rig: rig, gravity: g)
        // Tolerance on the system's energy scale, not `initial`, which can be zero.
        let scale = (rig.mass1 + rig.mass2) * g * (rig.length1 + rig.length2)
        XCTAssertEqual(final, initial, accuracy: scale * 1e-3,
                       "energy drifted; the equations of motion are not conservative")
    }

    /// Divergence proves the coupling survived. Assert on amplification, not
    /// absolute separation: Lyapunov ≈ 0.6/s, so 1e-6 rad grows ~1000x in 12 s.
    func testNearbyStartsDivergeExponentially() {
        let perturbation = 1e-6
        var a = DoublePendulum(theta1: 1.6, theta2: 1.5)
        var b = DoublePendulum(theta1: 1.6 + perturbation, theta2: 1.5)
        let dt = 1.0 / 240
        for _ in 0..<(240 * 12) {
            a = DoublePendulum.step(a, dt: dt, rig: rig, gravity: g)
            b = DoublePendulum.step(b, dt: dt, rig: rig, gravity: g)
        }
        let amplification = abs(a.theta2 - b.theta2) / perturbation
        XCTAssertGreaterThan(amplification, 100, """
            a micro-radian of difference grew only \(amplification)x over \
            twelve seconds. Exponential divergence is the signature of the \
            coupling between the two rods — check it survived.
            """)
    }

    // MARK: The linear limit

    /// Small-angle normal modes: for equal lengths and masses, ω² = (2 ∓ √2)g/L.
    func testEqualRigNormalModesMatchTheTextbookFrequencies() throws {
        let modes = try XCTUnwrap(
            DoublePendulum.normalModeFrequencies(rig: rig, gravity: g))
        let l = rig.length1
        let slow = ((2 - 2.0.squareRoot()) * g / l).squareRoot()
        let fast = ((2 + 2.0.squareRoot()) * g / l).squareRoot()
        XCTAssertEqual(modes.0, slow, accuracy: slow * 1e-9)
        XCTAssertEqual(modes.1, fast, accuracy: fast * 1e-9)
    }

    /// The simulation itself runs at the slow mode; the equal rig's in-phase
    /// mode has θ₂ = √2·θ₁.
    func testTheSimulationOscillatesAtItsSlowNormalMode() throws {
        let modes = try XCTUnwrap(
            DoublePendulum.normalModeFrequencies(rig: rig, gravity: g))
        let period = 2 * Double.pi / modes.0

        let amplitude = 0.02          // small enough for the linear theory
        var state = DoublePendulum(theta1: amplitude,
                                   theta2: amplitude * 2.0.squareRoot())
        let dt = 1.0 / 2000
        for _ in 0..<Int((period / dt).rounded()) {
            state = DoublePendulum.step(state, dt: dt, rig: rig, gravity: g)
        }
        XCTAssertEqual(state.theta1, amplitude, accuracy: amplitude * 0.02,
                       "one slow-mode period did not bring the upper rod home")
        XCTAssertEqual(state.theta2, amplitude * 2.0.squareRoot(),
                       accuracy: amplitude * 0.03)
    }

    // MARK: The degenerate limit

    /// Vanishing lower mass leaves a simple pendulum with period 2π√(L/g).
    func testAVanishingLowerMassLeavesASimplePendulum() {
        let light = DoublePendulum.Rig(length1: 0.5, length2: 0.5,
                                       mass1: 1.0, mass2: 1e-9)
        var state = DoublePendulum(theta1: 0.02, theta2: 0.02)
        let dt = 1.0 / 4000
        let period = 2 * Double.pi * (light.length1 / g).squareRoot()
        for _ in 0..<Int((period / dt).rounded()) {
            state = DoublePendulum.step(state, dt: dt, rig: light, gravity: g)
        }
        XCTAssertEqual(state.theta1, 0.02, accuracy: 0.02 * 0.02,
                       "the upper rod is not behaving like a simple pendulum")
    }

    // MARK: Geometry and guards

    func testBobPositionsFollowTheAngles() {
        // Hanging straight down.
        let down = DoublePendulum(theta1: 0, theta2: 0)
        XCTAssertEqual(down.upperBob(rig: rig).y, -0.5, accuracy: 1e-12)
        XCTAssertEqual(down.lowerBob(rig: rig).y, -1.0, accuracy: 1e-12)
        XCTAssertEqual(down.lowerBob(rig: rig).x, 0, accuracy: 1e-12)

        // Upper rod horizontal, lower rod straight down from its end.
        let bent = DoublePendulum(theta1: .pi / 2, theta2: 0)
        XCTAssertEqual(bent.upperBob(rig: rig).x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(bent.upperBob(rig: rig).y, 0, accuracy: 1e-12)
        XCTAssertEqual(bent.lowerBob(rig: rig).x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(bent.lowerBob(rig: rig).y, -0.5, accuracy: 1e-12)
    }

    func testADegenerateRigDoesNotProduceNaN() {
        let broken = DoublePendulum.Rig(length1: 0, length2: 0,
                                        mass1: 0, mass2: 0)
        let state = DoublePendulum.step(DoublePendulum(theta1: 1, theta2: 1),
                                        dt: 1.0 / 90, rig: broken, gravity: g)
        XCTAssertFalse(state.theta1.isNaN || state.theta2.isNaN
                       || state.omega1.isNaN || state.omega2.isNaN)
    }

    /// Damping must remove energy, never add it.
    func testDampingOnlyEverRemovesEnergy() {
        let damped = DoublePendulum.Rig(length1: 0.5, length2: 0.5,
                                        mass1: 1, mass2: 1, damping: 0.4)
        var state = DoublePendulum(theta1: 1.2, theta2: 0.9)
        var previous = state.energy(rig: damped, gravity: g)
        for _ in 0..<(240 * 6) {
            state = DoublePendulum.step(state, dt: 1.0 / 240,
                                        rig: damped, gravity: g)
            let now = state.energy(rig: damped, gravity: g)
            XCTAssertLessThanOrEqual(now, previous + 1e-6,
                                     "a damped double pendulum gained energy")
            previous = now
        }
    }

    // MARK: The bobs' velocities

    /// Bob velocities checked against a finite difference of the position
    /// accessor, so this cannot pass by repeating the same algebra mistake.
    func testBobVelocitiesMatchTheDerivativeOfTheirPositions() {
        let rig = DoublePendulum.Rig(length1: 0.42, length2: 0.31,
                                     mass1: 0.8, mass2: 1.3, damping: 0)
        var state = DoublePendulum(theta1: 1.1, theta2: -0.6,
                                   omega1: 0.9, omega2: -1.7)

        // A few steps in, so the check is not run at a symmetric start.
        for _ in 0..<40 {
            state = DoublePendulum.step(state, dt: 1.0 / 480, rig: rig, gravity: g)
        }

        let h = 1e-6
        for (name, position, velocity) in [
            ("upper", { (s: DoublePendulum) in s.upperBob(rig: rig) },
             state.upperBobVelocity(rig: rig)),
            ("lower", { (s: DoublePendulum) in s.lowerBob(rig: rig) },
             state.lowerBobVelocity(rig: rig)),
        ] as [(String, (DoublePendulum) -> SIMD2<Double>, SIMD2<Double>)] {
            // Advance the angles analytically by h at the current rates.
            var ahead = state
            ahead.theta1 += state.omega1 * h
            ahead.theta2 += state.omega2 * h
            var behind = state
            behind.theta1 -= state.omega1 * h
            behind.theta2 -= state.omega2 * h

            let numeric = (position(ahead) - position(behind)) / (2 * h)
            XCTAssertEqual(velocity.x, numeric.x, accuracy: 1e-6,
                           "\(name) bob's x velocity")
            XCTAssertEqual(velocity.y, numeric.y, accuracy: 1e-6,
                           "\(name) bob's y velocity")
        }
    }

    /// A rig at rest has bobs at rest — the trail gate's degenerate case.
    func testBobsAtRestReportNoSpeed() {
        let rig = DoublePendulum.Rig(length1: 0.5, length2: 0.5,
                                     mass1: 1, mass2: 1, damping: 0)
        let state = DoublePendulum(theta1: 0.7, theta2: 1.4)
        XCTAssertEqual(simd_length(state.lowerBobVelocity(rig: rig)), 0,
                       accuracy: 1e-12)
    }

    /// With both rods straight down all kinetic energy is in the bobs, so
    /// speed and energy must agree.
    func testSpeedAgreesWithKineticEnergyAtTheBottom() {
        let rig = DoublePendulum.Rig(length1: 0.5, length2: 0.5,
                                     mass1: 1, mass2: 1, damping: 0)
        let state = DoublePendulum(theta1: 0, theta2: 0,
                                   omega1: 2.0, omega2: 3.0)
        let upper = state.upperBobVelocity(rig: rig)
        let lower = state.lowerBobVelocity(rig: rig)
        let kinetic = 0.5 * rig.mass1 * simd_length_squared(upper)
            + 0.5 * rig.mass2 * simd_length_squared(lower)

        // `energy` is potential + kinetic with the pivot as datum.
        let potential = -g * (rig.mass1 * rig.length1
            + rig.mass2 * (rig.length1 + rig.length2))
        XCTAssertEqual(state.energy(rig: rig, gravity: g),
                       kinetic + potential, accuracy: 1e-9)
    }
}
