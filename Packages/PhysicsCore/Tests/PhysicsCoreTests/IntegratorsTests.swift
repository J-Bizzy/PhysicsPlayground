//
//  IntegratorsTests.swift
//  PhysicsCoreTests
//
//  Tests for the RK4 integrator. The oracles are systems with exact
//  solutions: constant acceleration (RK4 must be *exact* — the parabola is
//  a polynomial RK4 integrates without error) and simple harmonic motion
//  (checks accuracy and 4th-order convergence).
//

import XCTest
import simd
@testable import PhysicsCore

final class IntegratorsTests: XCTestCase {

    typealias State = ParticleDynamics.State

    /// Constant acceleration: RK4 reproduces r = r₀ + v₀t + ½at² exactly.
    func testConstantAccelerationIsExact() {
        let a = SIMD3<Double>(0, -9.81, 0)
        var state = State(position: .zero, velocity: SIMD3(3, 4, 0))
        let dt = 0.02
        let steps = 100
        for _ in 0..<steps {
            state = Integrators.rk4Step(state, dt: dt) { _, _ in a }
        }
        let t = Double(steps) * dt
        let expected = SIMD3(3, 4, 0) * t + 0.5 * a * t * t
        XCTAssertEqual(state.position.x, expected.x, accuracy: 1e-12)
        XCTAssertEqual(state.position.y, expected.y, accuracy: 1e-12)
        XCTAssertEqual(state.velocity.y, (SIMD3(3, 4, 0) + a * t).y, accuracy: 1e-12)
    }

    /// SHM a = −ω²r: after one full period the state must return to the
    /// start with tiny error at a reasonable step size.
    func testHarmonicOscillatorClosesAfterOnePeriod() {
        let omega = 2.0
        let period = 2 * Double.pi / omega
        let steps = 1000
        let dt = period / Double(steps)

        var state = State(position: SIMD3(1, 0, 0), velocity: .zero)
        for _ in 0..<steps {
            state = Integrators.rk4Step(state, dt: dt) { r, _ in -omega * omega * r }
        }
        XCTAssertEqual(state.position.x, 1.0, accuracy: 1e-9)
        XCTAssertEqual(state.velocity.x, 0.0, accuracy: 1e-8)
    }

    /// Halving the step size must cut the error by ~2⁴ (4th-order method).
    func testFourthOrderConvergence() {
        let omega = 3.0
        let duration = 1.0

        func endError(stepCount: Int) -> Double {
            let dt = duration / Double(stepCount)
            var state = State(position: SIMD3(1, 0, 0), velocity: .zero)
            for _ in 0..<stepCount {
                state = Integrators.rk4Step(state, dt: dt) { r, _ in -omega * omega * r }
            }
            // Exact solution: x(t) = cos(ωt).
            return abs(state.position.x - cos(omega * duration))
        }

        let coarse = endError(stepCount: 50)
        let fine = endError(stepCount: 100)
        XCTAssertGreaterThan(coarse / fine, 10,
                             "halving dt should shrink the error ~16×; got \(coarse / fine)")
    }
}
