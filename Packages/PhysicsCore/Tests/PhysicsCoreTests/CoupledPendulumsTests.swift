//
//  CoupledPendulumsTests.swift
//  PhysicsCoreTests
//
//  Two pendulums and a spring, against the closed forms: each normal mode
//  swings at its own frequency, the beat hands the whole swing from one
//  bob to the other in half its period, energy holds over a minute, and a
//  swing across the spring barely couples at all — the 3-D signature a
//  one-dimensional model cannot show.
//

import XCTest
import simd
@testable import PhysicsCore

final class CoupledPendulumsTests: XCTestCase {

    private let g = 9.81
    private let length = 0.8
    private let mass = 1.0
    private let stiffness = 2.0
    private let separation = 0.4
    private let dt = 1.0 / 720.0

    /// Two identical pendulums whose spring is unstretched while they hang.
    private var rig: CoupledPendulums.Rig {
        CoupledPendulums.Rig(pivotA: SIMD3(0, 1.6, 0), pivotB: SIMD3(separation, 1.6, 0),
                             lengthA: length, lengthB: length, massA: mass, massB: mass,
                             stiffness: stiffness, restLength: separation)
    }

    /// A bob displaced by `angle` in the plane of `axis` (horizontal).
    private func bob(_ angle: Double, along axis: SIMD3<Double> = SIMD3(1, 0, 0)) -> SphericalPendulum {
        SphericalPendulum(position: axis * (length * sin(angle)) + SIMD3(0, -length * cos(angle), 0))
    }

    /// The angular frequency of bob A's swing along x, from its zero
    /// crossings over `seconds`.
    private func frequency(_ start: CoupledPendulums, seconds: Double) -> Double {
        var state = start
        var crossings: [Double] = []
        var previous = state.a.position.x
        let steps = Int(seconds / dt)
        for step in 1...steps {
            state = CoupledPendulums.step(state, dt: dt, rig: rig, gravity: g)
            let x = state.a.position.x
            if previous < 0, x >= 0 {
                // Interpolated to the crossing within the step.
                crossings.append((Double(step - 1) + previous / (previous - x)) * dt)
            }
            previous = x
        }
        let periods = Double(crossings.count - 1)
        return 2 * .pi * periods / (crossings.last! - crossings.first!)
    }

    func testEachNormalModeSwingsAtItsOwnFrequency() {
        let modes = CoupledPendulums.normalModes(length: length, mass: mass,
                                                 stiffness: stiffness, gravity: g)
        let angle = 1 * Double.pi / 180
        let together = CoupledPendulums(a: bob(angle), b: bob(angle))
        XCTAssertEqual(frequency(together, seconds: 20) / modes.inPhase, 1, accuracy: 1e-3)
        let apart = CoupledPendulums(a: bob(angle), b: bob(-angle))
        XCTAssertEqual(frequency(apart, seconds: 20) / modes.antiPhase, 1, accuracy: 1e-3)
    }

    /// Let go of one bob: half a beat later the other has nearly all of it.
    func testTheBeatHandsTheWholeSwingAcross() {
        let beat = CoupledPendulums.beatPeriod(length: length, mass: mass,
                                               stiffness: stiffness, gravity: g)
        var state = CoupledPendulums(a: bob(2 * .pi / 180), b: bob(0))
        let total = state.totalEnergy(rig: rig, gravity: g)
        // Track B's share near half a beat: its peak over a swing either side.
        var peak = 0.0
        let half = beat / 2
        let period = 2 * .pi / (g / length).squareRoot()
        for step in 1...Int((half + period) / dt) {
            state = CoupledPendulums.step(state, dt: dt, rig: rig, gravity: g)
            let time = Double(step) * dt
            guard time > half - period else { continue }
            let e = state.energies(rig: rig, gravity: g)
            let bobB = e.kineticB + mass * g * (state.b.position.y + length)
            peak = max(peak, bobB / total)
        }
        XCTAssertGreaterThan(peak, 0.98, "the swing did not pass to the other bob")
    }

    /// Undamped, energy wanders by O(dt²) and does not drift: the mean over
    /// the last five seconds of a minute matches the first five.
    func testEnergyHoldsForAMinute() {
        var state = CoupledPendulums(a: bob(0.3), b: bob(-0.1, along: simd_normalize(SIMD3(1, 0, 1))))
        let start = state.totalEnergy(rig: rig, gravity: g)
        var first = 0.0, last = 0.0, worst = 0.0
        let window = Int(5 / dt), steps = Int(60 / dt)
        for step in 1...steps {
            state = CoupledPendulums.step(state, dt: dt, rig: rig, gravity: g)
            let e = state.totalEnergy(rig: rig, gravity: g)
            worst = max(worst, abs(e - start) / start)
            if step <= window { first += e }
            if step > steps - window { last += e }
        }
        XCTAssertLessThan(worst, 1e-4, "the energy wandered too far")
        XCTAssertLessThan(abs(last - first) / first, 1e-6, "the energy drifted")
        // And the cables never stretched.
        XCTAssertEqual(simd_length(state.a.position), length, accuracy: 1e-12)
        XCTAssertEqual(simd_length(state.b.position), length, accuracy: 1e-12)
    }

    /// Swung across the spring rather than along it, the spring's length
    /// changes only at second order, so almost nothing passes across.
    func testASwingAcrossTheSpringBarelyCouples() {
        var state = CoupledPendulums(a: bob(2 * .pi / 180, along: SIMD3(0, 0, 1)), b: bob(0))
        let total = state.totalEnergy(rig: rig, gravity: g)
        var peak = 0.0
        for _ in 0..<Int(30 / dt) {
            state = CoupledPendulums.step(state, dt: dt, rig: rig, gravity: g)
            let e = state.energies(rig: rig, gravity: g)
            peak = max(peak, (e.kineticB + mass * g * (state.b.position.y + length)) / total)
        }
        XCTAssertLessThan(peak, 0.01)
    }

    /// A held bob stays where the hand has it, and still drives the other.
    func testAHeldBobStaysButStillPulls() {
        var state = CoupledPendulums(a: bob(0.3), b: bob(0))
        let held = state.a.position
        for _ in 0..<720 {
            state = CoupledPendulums.step(state, dt: dt, rig: rig, gravity: g, heldA: true)
        }
        XCTAssertEqual(state.a.position, held)
        XCTAssertEqual(state.a.velocity, .zero)
        XCTAssertGreaterThan(abs(state.b.position.x), 1e-3, "the held bob's spring pulled nothing")
    }

    /// Hanging still with the spring at its natural length, each cable
    /// carries exactly its bob's weight.
    func testAtRestEachCableCarriesItsBobsWeight() {
        let state = CoupledPendulums(a: bob(0), b: bob(0))
        let tensions = state.tensions(rig: rig, gravity: g)
        XCTAssertEqual(tensions.a, mass * g, accuracy: 1e-12)
        XCTAssertEqual(tensions.b, mass * g, accuracy: 1e-12)
    }
}
