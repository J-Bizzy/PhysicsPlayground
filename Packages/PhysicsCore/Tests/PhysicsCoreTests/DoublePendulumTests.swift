//
//  DoublePendulumTests.swift
//  PhysicsCoreTests
//
//  Chaos defeats the obvious test. Two runs from imperceptibly different
//  starts diverge exponentially, so "does the trajectory match a stored
//  reference" is not a test that can pass — and a test that pins a
//  chaotic trajectory is really pinning the floating-point behaviour of
//  one machine.
//
//  What chaos does NOT touch is checked instead, and all three are
//  results this code shares no arithmetic with: energy is conserved, the
//  small-angle normal modes have their analytic frequencies, and the
//  system degenerates to a simple pendulum when the lower mass vanishes.
//

import XCTest
import simd
@testable import PhysicsCore

final class DoublePendulumTests: XCTestCase {

    private let rig = DoublePendulum.Rig(length1: 0.5, length2: 0.5,
                                         mass1: 1.0, mass2: 1.0)
    private let g = 9.81

    // MARK: Energy

    /// The undamped system conserves energy. This is the single most
    /// informative test here: almost any error in the equations of
    /// motion — a wrong sign, a dropped coupling term, a mismatched
    /// angle convention — shows up as energy drifting, because the wrong
    /// system is not the Euler–Lagrange system of ANY Lagrangian.
    ///
    /// Run hard, from a genuinely chaotic start (both rods near
    /// horizontal), for 20 s at 1/240 s. RK4's O(h⁵) local error leaves
    /// well under a tenth of a percent over that.
    func testEnergyIsConservedThroughChaoticMotion() {
        var state = DoublePendulum(theta1: 1.6, theta2: 1.5)
        let initial = state.energy(rig: rig, gravity: g)
        let dt = 1.0 / 240
        for _ in 0..<(240 * 20) {
            state = DoublePendulum.step(state, dt: dt, rig: rig, gravity: g)
        }
        let final = state.energy(rig: rig, gravity: g)
        // Referenced to the ENERGY SCALE of the system, not to `initial`,
        // which passes through zero for some rigs.
        let scale = (rig.mass1 + rig.mass2) * g * (rig.length1 + rig.length2)
        XCTAssertEqual(final, initial, accuracy: scale * 1e-3,
                       "energy drifted; the equations of motion are not conservative")
    }

    /// …and it really is chaotic, which is worth pinning too: a double
    /// pendulum that did NOT diverge would mean the coupling term was
    /// lost and this is secretly two independent pendulums.
    ///
    /// The assertion is on the AMPLIFICATION, not on an absolute
    /// separation, and that distinction is the point. Exponential
    /// divergence is a statement about a ratio — this rig's Lyapunov
    /// exponent is around 0.6 per second, so a micro-radian becomes a
    /// milliradian in twelve seconds and would need about nineteen to
    /// reach a tenth of a radian. The first version of this test asked
    /// for 0.1 after twelve seconds and failed on a system that was
    /// diverging perfectly well — a test measuring the wrong quantity
    /// rather than a physics fault. A thousandfold growth from a
    /// perturbation this small cannot happen in a linear system.
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

    /// At small angles the system must oscillate at the two analytic
    /// normal-mode frequencies. For equal lengths and equal masses those
    /// are ω² = (2 ∓ √2)g/L, which is a textbook result derived
    /// independently of anything in `acceleration`.
    func testEqualRigNormalModesMatchTheTextbookFrequencies() throws {
        let modes = try XCTUnwrap(
            DoublePendulum.normalModeFrequencies(rig: rig, gravity: g))
        let l = rig.length1
        let slow = ((2 - 2.0.squareRoot()) * g / l).squareRoot()
        let fast = ((2 + 2.0.squareRoot()) * g / l).squareRoot()
        XCTAssertEqual(modes.0, slow, accuracy: slow * 1e-9)
        XCTAssertEqual(modes.1, fast, accuracy: fast * 1e-9)
    }

    /// The frequencies are not just algebra — the SIMULATION runs at
    /// them. Started exactly in the slow (in-phase) mode, both rods must
    /// return to their start after one period of that mode.
    ///
    /// The in-phase mode for the equal rig has θ₂ = √2·θ₁.
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

    /// With a vanishing lower mass the upper rod is a simple pendulum,
    /// and must keep the simple pendulum's small-angle period 2π√(L/g).
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

    /// THE ACCESSOR THE WHOLE RIG WAS MISSING. `DoublePendulum` reported
    /// only where the bobs ARE, so nothing downstream could ask how fast
    /// the chaotic bob was moving — and Pendulums' trail, velocity
    /// arrow, readout card and freeze sculpt all silently believed the
    /// answer was zero.
    ///
    /// Checked against a finite difference of the POSITION accessor
    /// rather than against a second copy of the algebra, so this cannot
    /// pass by making the same differentiation mistake twice.
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
            // Advance the ANGLES analytically by h at the current rates;
            // over an interval this short that is the definition of the
            // derivative the accessor claims to compute.
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

    /// A rig at rest has bobs at rest — the degenerate case the trail
    /// gate actually tests against.
    func testBobsAtRestReportNoSpeed() {
        let rig = DoublePendulum.Rig(length1: 0.5, length2: 0.5,
                                     mass1: 1, mass2: 1, damping: 0)
        let state = DoublePendulum(theta1: 0.7, theta2: 1.4)
        XCTAssertEqual(simd_length(state.lowerBobVelocity(rig: rig)), 0,
                       accuracy: 1e-12)
    }

    /// And a moving one reports a speed the energy agrees with: at the
    /// instant both rods are straight down, all the kinetic energy is in
    /// the bobs and the two calculations must meet.
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
