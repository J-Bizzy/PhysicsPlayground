//
//  DipoleDynamicsTests.swift
//  PhysicsCoreTests
//
//  Theorem recovery from integrated swings — T = 2π√(I/mB) is measured from
//  the simulation; `step` is never told the formula.
//

import XCTest
import simd
@testable import PhysicsCore

final class DipoleDynamicsTests: XCTestCase {

    /// A magnet of the bench's own proportions: 16 cm, 6 A·m².
    private let length = 0.16
    private let strength = 6.0

    private var inertia: Double {
        DipoleDynamics.momentOfInertia(moment: strength, length: length)
    }

    /// Swings a needle in a uniform +x field, returning the plane angle each
    /// step. Undamped unless asked — the formula is for the free period.
    private func swing(
        startAngle: Double,
        field: SIMD3<Double>,
        damping: Double = 0,
        seconds: Double,
        dt: Double = 1.0 / 2000
    ) -> [(t: Double, angle: Double)] {
        var moment = SIMD3(cos(startAngle), sin(startAngle), 0) * strength
        var position = SIMD3<Double>.zero
        var body = DipoleBody()
        let mass = DipoleDynamics.mass(moment: strength)
        let I = inertia

        var samples: [(Double, Double)] = []
        var t = 0.0
        while t < seconds {
            let torque = simd_cross(moment, field)
            DipoleDynamics.step(
                body: &body, position: &position, moment: &moment,
                force: .zero, torque: torque,
                mass: mass, momentOfInertia: I, damping: damping, dt: dt)
            t += dt
            // Signed angle from the field direction, in the swing plane.
            samples.append((t, atan2(moment.y, moment.x)))
        }
        return samples
    }

    // MARK: Overshoot

    /// A released needle must swing PAST alignment — impossible without
    /// inertia, which is why the type exists.
    func testAReleasedNeedleSwingsPastAlignmentAndComesBack() {
        let samples = swing(startAngle: 0.35, field: SIMD3(5e-5, 0, 0),
                            seconds: 4)
        let angles = samples.map(\.angle)

        XCTAssertLessThan(angles.min() ?? 0, -0.30,
                          """
                          The needle never crossed alignment. It started at \
                          +0.35 rad and the most negative angle reached was \
                          \(angles.min() ?? 0). Without inertia this test is \
                          impossible to pass — which is the point of it.
                          """)
        XCTAssertGreaterThan(angles.max() ?? 0, 0.30,
                             "And it must come back to where it started.")
    }

    /// T = 2π√(I/mB) recovered at three fields (period ∝ 1/√B). Release at
    /// 0.05 rad: the formula is the small-oscillation limit (grows as 1 + θ₀²/16).
    func testTheMagnetometerPeriodIsRecovered() {
        for field in [2.5e-5, 5e-5, 1e-4] {
            let expected = DipoleDynamics.smallOscillationPeriod(
                momentMagnitude: strength, fieldMagnitude: field,
                momentOfInertia: inertia)

            let samples = swing(startAngle: 0.05,
                                field: SIMD3(field, 0, 0),
                                seconds: expected * 2.5)
            let measured = try! XCTUnwrap(period(of: samples),
                                          "No full cycle at B = \(field) T.")

            XCTAssertEqual(measured, expected, accuracy: expected * 0.02,
                           """
                           At B = \(field) T the swing took \(measured) s \
                           against 2π√(I/mB) = \(expected) s.
                           """)
        }
    }

    /// One full cycle between the first and third upward zero crossings.
    private func period(of samples: [(t: Double, angle: Double)]) -> Double? {
        var crossings: [Double] = []
        for index in 1..<samples.count {
            let before = samples[index - 1], now = samples[index]
            if before.angle <= 0, now.angle > 0 {
                // Interpolate to the zero so the answer is not quantised by the step.
                let span = now.angle - before.angle
                let fraction = span.magnitude > 1e-18 ? -before.angle / span : 0
                crossings.append(before.t + fraction * (now.t - before.t))
            }
        }
        guard crossings.count >= 2 else { return nil }
        return crossings[1] - crossings[0]
    }

    // MARK: Energy

    /// Undamped energy (½Iω² − m·B) must stay BOUNDED — semi-implicit Euler
    /// does not conserve exactly, but must not grow.
    func testAnUndampedSwingKeepsItsEnergy() {
        let field = SIMD3(5e-5, 0.0, 0.0)
        var moment = SIMD3(cos(0.4), sin(0.4), 0) * strength
        var position = SIMD3<Double>.zero
        var body = DipoleBody()
        let mass = DipoleDynamics.mass(moment: strength)
        let I = inertia

        func energy() -> Double {
            let rate = simd_length(body.angularVelocity)
            return 0.5 * I * rate * rate - simd_dot(moment, field)
        }
        let start = energy()
        // Tolerance scale: the energy the swing carries, not a potential with arbitrary zero.
        let swingEnergy = simd_length(moment) * simd_length(field) * (1 - cos(0.4))

        for _ in 0..<40_000 {
            let torque = simd_cross(moment, field)
            DipoleDynamics.step(
                body: &body, position: &position, moment: &moment,
                force: .zero, torque: torque,
                mass: mass, momentOfInertia: I, damping: 0, dt: 1.0 / 2000)
            XCTAssertEqual(energy(), start, accuracy: swingEnergy * 0.01)
        }
    }

    /// Damped energy falls monotonically; `step` applies damping as a decay
    /// factor rather than −γv·dt, which can pump energy at a coarse step.
    func testDampingOnlyEverRemovesEnergy() {
        let field = SIMD3(5e-5, 0.0, 0.0)
        var moment = SIMD3(cos(0.6), sin(0.6), 0) * strength
        var position = SIMD3<Double>.zero
        var body = DipoleBody()
        let I = inertia

        func energy() -> Double {
            let rate = simd_length(body.angularVelocity)
            return 0.5 * I * rate * rate - simd_dot(moment, field)
        }

        var previous = energy()
        // Deliberately coarse step + heavy damping — the regime where −γv·dt fails.
        for _ in 0..<2_000 {
            let torque = simd_cross(moment, field)
            DipoleDynamics.step(
                body: &body, position: &position, moment: &moment,
                force: .zero, torque: torque,
                mass: DipoleDynamics.mass(moment: strength),
                momentOfInertia: I, damping: 40, dt: 1.0 / 90)
            let now = energy()
            XCTAssertLessThanOrEqual(now, previous + abs(previous) * 1e-9,
                                     "Damping added energy.")
            previous = now
        }
    }

    /// It must actually come to rest, not merely lose energy slowly.
    func testADampedNeedleSettlesOnAlignment() {
        let field = SIMD3(5e-5, 0.0, 0.0)
        let samples = swing(startAngle: 0.8, field: field,
                            damping: 1.2, seconds: 60, dt: 1.0 / 500)
        let settled = samples.suffix(200).map(\.angle)
        for angle in settled {
            XCTAssertEqual(angle, 0, accuracy: 0.01,
                           "The needle should be pointing along the field.")
        }
    }

    // MARK: The derived bar

    /// Mass derives from moment through the material: twice the moment is
    /// twice the mass; twice the volume at fixed length is √2× the radius.
    func testAStrongerMagnetIsABiggerHeavierBar() {
        let weak = DipoleDynamics.mass(moment: 3)
        let strong = DipoleDynamics.mass(moment: 6)
        XCTAssertEqual(strong, weak * 2, accuracy: weak * 1e-9)

        let thin = DipoleDynamics.radius(moment: 3, length: length)
        let thick = DipoleDynamics.radius(moment: 6, length: length)
        XCTAssertEqual(thick, thin * 2.0.squareRoot(), accuracy: thin * 1e-9)
    }

    /// Sanity: the bench magnet is a plausible object (~45 g, ~7 mm across,
    /// seconds-scale period in Earth's field), not just algebra-consistent.
    func testTheBenchMagnetIsAPhysicallyPlausibleObject() {
        XCTAssertEqual(DipoleDynamics.mass(moment: strength), 0.045,
                       accuracy: 0.005)
        XCTAssertEqual(DipoleDynamics.radius(moment: strength, length: length),
                       0.0035, accuracy: 0.0005)
        let earth = DipoleDynamics.smallOscillationPeriod(
            momentMagnitude: strength, fieldMagnitude: 5e-5,
            momentOfInertia: inertia)
        XCTAssertGreaterThan(earth, 1.0, "A compass needle is not a blur.")
        XCTAssertLessThan(earth, 10.0, "Nor is it a minute hand.")
    }

    /// L² dominates I (the 3r² term is ~0.14% at these proportions) — the
    /// licence for treating a magnet's thickness as a detail elsewhere.
    func testTheLengthDominatesTheInertia() {
        let full = DipoleDynamics.momentOfInertia(moment: strength, length: length)
        let asRod = DipoleDynamics.mass(moment: strength) * length * length / 12
        XCTAssertEqual(full, asRod, accuracy: asRod * 0.002)
        XCTAssertGreaterThan(full, asRod,
                             "The radius can only ADD to a rod's inertia.")
    }
}
