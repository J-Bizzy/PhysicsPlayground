//
//  DipoleDynamicsTests.swift
//  PhysicsCoreTests
//
//  Theorem recovery, in the shape `FoucaultTests` established: nothing
//  here asserts that a formula returns what the formula says. Every test
//  integrates a swinging magnet and measures what it did.
//
//  The headline is the magnetometer period, T = 2π√(I/mB). It is
//  recovered from a simulated swing at three field strengths, and
//  `smallOscillationPeriod` is used only to say what the answer SHOULD
//  be — `step` is never told it. That is the difference between checking
//  the physics and checking the arithmetic twice.
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

    /// Swings a needle in a uniform field along +x, released at `angle`
    /// from alignment, and returns the plane angle each step.
    ///
    /// Undamped unless asked, because a period measured through damping
    /// is a damped period and the formula is for the free one.
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

    // MARK: The thing the mobility bench could not do

    /// **A NEEDLE RELEASED AT AN ANGLE SWINGS PAST ALIGNMENT.**
    ///
    /// This is the whole reason the type exists. The overdamped bench it
    /// replaces could not overshoot by construction — no inertia, so the
    /// angle decreases monotonically to zero and stops. Here it must
    /// cross.
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

    /// **T = 2π√(I/mB), recovered at three field strengths.**
    ///
    /// The period must scale as 1/√B — quadrupling the field must halve
    /// the period — and that is a stronger claim than any single value,
    /// because a wrong inertia or a wrong torque would move all three
    /// together only if it were wrong in exactly the right way.
    ///
    /// A small release angle (0.05 rad) because the formula is the
    /// SMALL-oscillation limit: the real pendulum period grows as
    /// 1 + θ₀²/16, which at 0.05 rad is 2 parts in 10⁵ and at 0.35 rad
    /// would be 0.8 % — bigger than the tolerance here.
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

    /// The period between the first and third upward zero crossings —
    /// one full cycle, measured rather than assumed.
    private func period(of samples: [(t: Double, angle: Double)]) -> Double? {
        var crossings: [Double] = []
        for index in 1..<samples.count {
            let before = samples[index - 1], now = samples[index]
            if before.angle <= 0, now.angle > 0 {
                // Linear interpolation to the zero, so the answer is not
                // quantised by the step.
                let span = now.angle - before.angle
                let fraction = span.magnitude > 1e-18 ? -before.angle / span : 0
                crossings.append(before.t + fraction * (now.t - before.t))
            }
        }
        guard crossings.count >= 2 else { return nil }
        return crossings[1] - crossings[0]
    }

    // MARK: Energy

    /// Undamped, the swing must keep its energy: rotational kinetic plus
    /// the dipole's −m·B. Semi-implicit Euler does not conserve it
    /// exactly, but it must stay BOUNDED rather than growing, which is
    /// the property that makes it the right scheme here.
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
        // The scale that matters: how much energy the swing carries, not
        // the absolute value of a potential with an arbitrary zero.
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

    /// Damped, the energy must fall monotonically. A drag that could add
    /// energy at a large step is the classic linear-damping bug, which
    /// is why `step` applies it as a decay factor rather than −γv·dt.
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
        // A deliberately COARSE step and heavy damping — the regime where
        // a naive −γv·dt would overshoot into negative velocity and pump
        // energy back in.
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

    /// The mass comes from the moment through the material, so a magnet
    /// twice as strong is twice as heavy — and that is what makes it
    /// slower to turn rather than a tuned constant.
    func testAStrongerMagnetIsABiggerHeavierBar() {
        let weak = DipoleDynamics.mass(moment: 3)
        let strong = DipoleDynamics.mass(moment: 6)
        XCTAssertEqual(strong, weak * 2, accuracy: weak * 1e-9)

        let thin = DipoleDynamics.radius(moment: 3, length: length)
        let thick = DipoleDynamics.radius(moment: 6, length: length)
        // Twice the volume at the same length is √2 times the radius.
        XCTAssertEqual(thick, thin * 2.0.squareRoot(), accuracy: thin * 1e-9)
    }

    /// The bench's own magnet should be a plausible object rather than a
    /// number that merely satisfies the algebra: about 45 g, about 7 mm
    /// across, with a period of a few seconds in Earth's field. If any
    /// of these drifts into the absurd, the derivation is wrong even
    /// though every relation above still holds.
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

    /// A bar is a rod: the L² term dominates I, so the radius barely
    /// matters. Worth pinning because it is the licence for treating a
    /// magnet's thickness as a detail everywhere else.
    ///
    /// The 3r² term carries 0.14 % at these proportions — 3(3.5 mm)²
    /// against (16 cm)². The first version of this test asserted 0.1 %,
    /// which was a guess at "negligible" rather than the arithmetic.
    func testTheLengthDominatesTheInertia() {
        let full = DipoleDynamics.momentOfInertia(moment: strength, length: length)
        let asRod = DipoleDynamics.mass(moment: strength) * length * length / 12
        XCTAssertEqual(full, asRod, accuracy: asRod * 0.002)
        XCTAssertGreaterThan(full, asRod,
                             "The radius can only ADD to a rod's inertia.")
    }
}
