//
//  OscillationsTests.swift
//  PhysicsCoreTests
//
//  The oscillation core against the textbook: small-angle pendulum
//  period, the nonlinear large-angle correction, energy conservation,
//  damping decay, the taut-cable constraint, spring period, and the
//  coupled-oscillator beat.
//

import XCTest
import simd
@testable import PhysicsCore

final class OscillationsTests: XCTestCase {

    private let dt = 1.0 / 1000.0

    /// Measure a full period by timing successive same-direction zero
    /// crossings of x.
    private func measuredPendulumPeriod(angle: Double, length: Double = 1.0,
                                        gravity: Double = 9.81) -> Double {
        var state = SphericalPendulum(length: length, angle: angle)
        var lastX = state.position.x
        var crossings: [Double] = []
        var time = 0.0
        while time < 20, crossings.count < 4 {
            state = SphericalPendulum.step(state, dt: dt, length: length,
                                           gravity: gravity, mass: 1, damping: 0)
            time += dt
            if lastX < 0, state.position.x >= 0 {
                crossings.append(time)
            }
            lastX = state.position.x
        }
        guard crossings.count >= 2 else { return .nan }
        return crossings[1] - crossings[0]
    }

    /// At 5° the simulated period matches 2π√(L/g) to a fraction of a
    /// percent — the small-angle limit falls out naturally.
    func testSmallAnglePeriodMatchesAnalytic() {
        let analytic = SphericalPendulum.smallAnglePeriod(length: 1, gravity: 9.81)
        let measured = measuredPendulumPeriod(angle: .pi / 36)
        XCTAssertEqual(measured, analytic, accuracy: analytic * 0.004)
    }

    /// At 60° the nonlinear period runs ~7.3% longer than small-angle —
    /// the exact series 1 + θ²/16 + 11θ⁴/3072 predicts it.
    func testLargeAnglePeriodShowsNonlinearity() {
        let theta = Double.pi / 3
        let analytic = SphericalPendulum.smallAnglePeriod(length: 1, gravity: 9.81)
        let corrected = analytic * (1 + theta * theta / 16
                                    + 11 * pow(theta, 4) / 3072)
        let measured = measuredPendulumPeriod(angle: theta)
        XCTAssertEqual(measured, corrected, accuracy: corrected * 0.005)
        XCTAssertGreaterThan(measured, analytic * 1.05,
                             "large swings must run measurably slow")
    }

    /// Undamped, total energy holds to a tiny fraction over thousands of
    /// steps, and the cable never stretches.
    func testEnergyConservationAndTautCable() {
        let length = 0.8
        var state = SphericalPendulum(length: length, angle: 1.0)
        let initial = state.energies(length: length, gravity: 9.81, mass: 2)
        let total0 = initial.kinetic + initial.potential
        for _ in 0..<8000 {
            state = SphericalPendulum.step(state, dt: dt, length: length,
                                           gravity: 9.81, mass: 2, damping: 0)
            XCTAssertEqual(simd_length(state.position), length, accuracy: 1e-9)
        }
        let final = state.energies(length: length, gravity: 9.81, mass: 2)
        XCTAssertEqual(final.kinetic + final.potential, total0,
                       accuracy: total0 * 0.01)
    }

    /// Damping bleeds energy monotonically toward zero.
    func testDampingDecays() {
        let length = 1.0
        var state = SphericalPendulum(length: length, angle: 0.8)
        for _ in 0..<20000 {
            state = SphericalPendulum.step(state, dt: dt, length: length,
                                           gravity: 9.81, mass: 1, damping: 0.4)
        }
        let energies = state.energies(length: length, gravity: 9.81, mass: 1)
        XCTAssertLessThan(energies.kinetic + energies.potential, 0.4,
                          "most of the initial energy must be gone")
    }

    /// A sideways throw makes a genuinely 3D orbit: the bob leaves the
    /// launch plane while staying on the sphere.
    func testSidewaysThrowGoesThreeDimensional() {
        let length = 1.0
        var state = SphericalPendulum(length: length, angle: 0.5)
        state.velocity = SIMD3(0, 0, 0.9)
        var maxOutOfPlane = 0.0
        for _ in 0..<3000 {
            state = SphericalPendulum.step(state, dt: dt, length: length,
                                           gravity: 9.81, mass: 1, damping: 0)
            maxOutOfPlane = max(maxOutOfPlane, abs(state.position.z))
        }
        XCTAssertGreaterThan(maxOutOfPlane, 0.2)
        XCTAssertEqual(simd_length(state.position), length, accuracy: 1e-9)
    }

    /// Spring period matches 2π√(m/k) and undamped energy holds.
    func testSpringPeriodAndEnergy() {
        let stiffness = 40.0, mass = 0.5
        var state = SpringOscillator(displacement: 0.1)
        let analytic = SpringOscillator.period(stiffness: stiffness, mass: mass)

        var lastX = state.displacement
        var crossings: [Double] = []
        var time = 0.0
        while time < 5, crossings.count < 3 {
            state = SpringOscillator.step(state, dt: dt, stiffness: stiffness,
                                          mass: mass, damping: 0)
            time += dt
            if lastX < 0, state.displacement >= 0 { crossings.append(time) }
            lastX = state.displacement
        }
        XCTAssertEqual(crossings[1] - crossings[0], analytic,
                       accuracy: analytic * 0.004)

        let energies = state.energies(stiffness: stiffness, mass: mass)
        XCTAssertEqual(energies.kinetic + energies.potential,
                       0.5 * stiffness * 0.01, accuracy: 0.5 * stiffness * 0.01 * 0.01)
    }

    /// Gravity along the axis just shifts the equilibrium to mg/k.
    func testSpringBiasForceShiftsEquilibrium() {
        var state = SpringOscillator(displacement: 0)
        for _ in 0..<40000 {
            state = SpringOscillator.step(state, dt: dt, stiffness: 20, mass: 1,
                                          damping: 2, biasForce: -9.81)
        }
        XCTAssertEqual(state.displacement, -9.81 / 20, accuracy: 1e-3)
    }

    /// The showcase: displace mass 1 only, and the energy migrates to
    /// mass 2 and back — a beat, straight from the equations.
    func testCoupledSpringsExchangeEnergy() {
        let stiffness = 30.0, coupling = 4.0
        let masses = SIMD2(1.0, 1.0)
        var state = CoupledSprings(displacements: SIMD2(0.1, 0))
        let start = state.massEnergies(stiffness: stiffness, coupling: coupling, masses: masses)
        XCTAssertGreaterThan(start.x, start.y * 5, "energy starts on mass 1")

        // The full transfer takes half a beat: T = 2π/(ω2−ω1).
        let omega1 = (stiffness / masses.x).squareRoot()
        let omega2 = ((stiffness + 2 * coupling) / masses.x).squareRoot()
        let halfBeat = .pi / (omega2 - omega1)
        var maxOnTwo = 0.0
        var time = 0.0
        while time < halfBeat * 1.2 {
            state = CoupledSprings.step(state, dt: dt, stiffness: stiffness,
                                        coupling: coupling, masses: masses, damping: 0)
            time += dt
            let energies = state.massEnergies(stiffness: stiffness, coupling: coupling, masses: masses)
            maxOnTwo = max(maxOnTwo, energies.y / (energies.x + energies.y))
        }
        XCTAssertGreaterThan(maxOnTwo, 0.9,
                             "nearly all the energy must visit mass 2")
    }
}
