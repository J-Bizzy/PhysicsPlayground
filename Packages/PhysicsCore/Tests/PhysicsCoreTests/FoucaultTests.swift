//
//  FoucaultTests.swift
//  PhysicsCoreTests
//
//  Theorem recovery, not formula consistency.
//
//  This project learned the difference the expensive way: the Wind
//  Tunnel's pressure-integration test caught a real vortex-term sign
//  error precisely because it recovered Kutta–Joukowski from the
//  simulation instead of restating it. So nothing here asserts that
//  `precessionRate` returns Ω sin φ — that would only prove the formula
//  is typed the same way twice. Every test below INTEGRATES a swinging
//  pendulum and measures what the plane actually did.
//

import XCTest
import simd
@testable import PhysicsCore

final class FoucaultTests: XCTestCase {

    /// Swings a pendulum in a rotating frame and measures how far its
    /// plane turned, in rad/s, by unwrapping the plane angle.
    private func measuredPrecession(
        latitudeDegrees: Double, spin: Double,
        length: Double = 1.0, seconds: Double = 400, dt: Double = 1.0 / 720.0
    ) -> Double {
        let omega = EarthRotation.angularVelocity(latitudeDegrees: latitudeDegrees,
                                                  spin: spin)
        // Released from rest, swinging in the x–z plane along +x. A start
        // from REST is the honest one: give it a sideways velocity and it
        // traces an ellipse whose own precession would contaminate the
        // measurement.
        var state = SphericalPendulum(
            position: SIMD3(0.12, -(length * length - 0.0144).squareRoot(), 0),
            velocity: .zero)

        var previous = EarthRotation.planeAngle(of: SIMD2(state.position.x,
                                                          state.position.z))
        var unwrapped = previous
        var elapsed = 0.0
        while elapsed < seconds {
            state = SphericalPendulum.step(state, dt: dt, length: length,
                                           gravity: 9.81, mass: 1, damping: 0,
                                           angularVelocity: omega)
            elapsed += dt
            // Only sample near the swing's extremes, where the horizontal
            // displacement is large and its direction is well defined.
            // Near the bottom the bob passes through the pivot's vertical
            // and the "plane angle" of a near-zero vector is noise.
            let horizontal = SIMD2(state.position.x, state.position.z)
            guard simd_length(horizontal) > 0.06 else { continue }
            let angle = EarthRotation.planeAngle(of: horizontal)
            // The plane angle folds onto a half turn, so unwrap by π.
            var delta = angle - previous
            while delta > .pi / 2 { delta -= .pi }
            while delta < -.pi / 2 { delta += .pi }
            unwrapped += delta
            previous = angle
        }
        let start = EarthRotation.planeAngle(of: SIMD2(0.12, 0))
        return (unwrapped - start) / elapsed
    }

    /// THE SINE LAW, recovered from the integration at three latitudes.
    ///
    /// The spin is exaggerated so the effect is measurable in a few
    /// hundred simulated seconds rather than a few hundred hours; that is
    /// exactly what the app does, and the rate must still come out at
    /// Ω sin φ for the Ω actually integrated.
    func testMeasuredPrecessionFollowsOmegaSineLatitude() {
        let spin = 3000.0
        for latitude in [30.0, 45.0, 60.0] {
            let expected = EarthRotation.precessionRate(latitudeDegrees: latitude,
                                                        spin: spin)
            let measured = measuredPrecession(latitudeDegrees: latitude, spin: spin)
            // Sign convention: the plane angle is measured east-toward-
            // north, so a northern-hemisphere plane turning clockwise seen
            // from above DECREASES it.
            XCTAssertEqual(-measured, expected, accuracy: abs(expected) * 0.05,
                           "latitude \(latitude): measured \(-measured), law \(expected)")
        }
    }

    /// The equator is the law's zero, and it has to come out of the
    /// integration rather than out of a special case — Ω is NOT zero
    /// there, it is horizontal, and the horizontal component's effect
    /// must average away over the swing.
    func testAtTheEquatorThePlaneDoesNotTurn() {
        let omega = EarthRotation.angularVelocity(latitudeDegrees: 0, spin: 3000)
        XCTAssertGreaterThan(simd_length(omega), 0,
                             "Ω is horizontal at the equator, not absent")
        XCTAssertEqual(omega.y, 0, accuracy: 1e-18, "no vertical component")

        let measured = measuredPrecession(latitudeDegrees: 0, spin: 3000)
        let atFortyFive = abs(EarthRotation.precessionRate(latitudeDegrees: 45,
                                                           spin: 3000))
        XCTAssertLessThan(abs(measured), atFortyFive * 0.05,
                          "the plane turned on the equator")
    }

    /// At the pole the plane makes exactly one turn per sidereal day —
    /// the cleanest statement of the whole effect, and the case where
    /// "the ground turns underneath" is literally all that happens.
    func testAtThePoleThePlaneTurnsOncePerSiderealDay() {
        let period = try! XCTUnwrap(
            EarthRotation.precessionPeriod(latitudeDegrees: 90))
        XCTAssertEqual(period, EarthRotation.siderealDay, accuracy: 1e-6)

        let spin = 3000.0
        let measured = measuredPrecession(latitudeDegrees: 90, spin: spin)
        let expected = EarthRotation.angularSpeed * spin
        XCTAssertEqual(-measured, expected, accuracy: expected * 0.05)
    }

    /// The southern hemisphere turns the other way, and that falls out of
    /// sin(−φ) = −sin(φ) rather than being written anywhere.
    func testTheSouthernHemisphereTurnsTheOtherWay() {
        let north = measuredPrecession(latitudeDegrees: 45, spin: 3000)
        let south = measuredPrecession(latitudeDegrees: -45, spin: 3000)
        XCTAssertEqual(north, -south, accuracy: abs(north) * 0.08)
        XCTAssertGreaterThan(abs(north), 1e-9, "nothing moved at all")
    }

    /// CORIOLIS DOES NO WORK, so an undamped Foucault pendulum conserves
    /// energy exactly as an undamped ordinary one does.
    ///
    /// This is the sharp test of the term itself: any sign error, axis
    /// mix-up, or stray factor that put a component of the acceleration
    /// ALONG the velocity would pump or drain the swing, and would show
    /// here long before it showed as a wrong precession rate.
    func testCoriolisDoesNoWork() {
        let length = 1.0
        let omega = EarthRotation.angularVelocity(latitudeDegrees: 45, spin: 5000)
        var state = SphericalPendulum(
            position: SIMD3(0.2, -(length * length - 0.04).squareRoot(), 0),
            velocity: SIMD3(0, 0, 0.3))   // a genuinely 3-D start

        func energy(_ s: SphericalPendulum) -> Double {
            let e = s.energies(length: length, gravity: 9.81, mass: 1)
            return e.kinetic + e.potential
        }
        let before = energy(state)
        for _ in 0..<200_000 {
            state = SphericalPendulum.step(state, dt: 1.0 / 720.0, length: length,
                                           gravity: 9.81, mass: 1, damping: 0,
                                           angularVelocity: omega)
        }
        XCTAssertEqual(energy(state), before, accuracy: before * 1e-6,
                       "the Coriolis term is doing work, so it is wrong")
        XCTAssertEqual(simd_length(state.position), length, accuracy: 1e-9,
                       "the cable stopped being taut")
    }

    /// Ω = 0 must be the ordinary pendulum BIT FOR BIT, not merely
    /// close — the parameter defaults to `.zero` and every existing
    /// caller relies on nothing having changed underneath it.
    func testZeroRotationIsExactlyTheOldPendulum() {
        var withParameter = SphericalPendulum(length: 1.0, angle: 0.4)
        var without = SphericalPendulum(length: 1.0, angle: 0.4)
        for _ in 0..<5_000 {
            withParameter = SphericalPendulum.step(
                withParameter, dt: 1.0 / 720.0, length: 1, gravity: 9.81,
                mass: 1, damping: 0.05, angularVelocity: .zero)
            without = SphericalPendulum.step(
                without, dt: 1.0 / 720.0, length: 1, gravity: 9.81,
                mass: 1, damping: 0.05)
        }
        XCTAssertEqual(withParameter.position, without.position)
        XCTAssertEqual(withParameter.velocity, without.velocity)
    }

    /// The sidereal day, not the solar one. Getting this wrong is a
    /// four-minute error in the polar period — small, invisible, and
    /// exactly the sort of thing the project's claim rests on not doing.
    func testTheSiderealDayIsTheOneThatGoverns() {
        XCTAssertEqual(EarthRotation.siderealDay, 86_164.0905, accuracy: 1e-3)
        XCTAssertLessThan(EarthRotation.siderealDay, 86_400)
        XCTAssertEqual(EarthRotation.angularSpeed, 7.2921e-5, accuracy: 1e-9)

        // Paris: the real installation, and the number the room should
        // quote — about 11.3 degrees an hour, a full turn in ~31.8 hours.
        let paris = EarthRotation.sites.first { $0.name == "Paris" }!
        let rate = EarthRotation.precessionRate(
            latitudeDegrees: paris.latitudeDegrees)
        XCTAssertEqual(rate * 3600 * 180 / .pi, 11.30, accuracy: 0.05)
        let period = try! XCTUnwrap(EarthRotation.precessionPeriod(
            latitudeDegrees: paris.latitudeDegrees))
        XCTAssertEqual(period / 3600, 31.8, accuracy: 0.1)
    }

    /// The equator has no precession period, and that is an answer.
    func testTheEquatorHasNoPrecessionPeriod() {
        XCTAssertNil(EarthRotation.precessionPeriod(latitudeDegrees: 0))
        XCTAssertNotNil(EarthRotation.precessionPeriod(latitudeDegrees: 0.5))
    }

    /// A plane is a plane whichever way the bob happens to be going along
    /// it, so the reading folds onto a half turn and stays continuous
    /// through the fold. Straight `atan2` would jump by π every half
    /// swing — a discontinuity in the READOUT, not in the physics.
    func testThePlaneAngleFoldsOntoAHalfTurn() {
        let east = EarthRotation.planeAngle(of: SIMD2(1, 0))
        let west = EarthRotation.planeAngle(of: SIMD2(-1, 0))
        XCTAssertEqual(east, west, accuracy: 1e-12,
                       "the same plane read two different ways")

        // A quarter turn of the PLANE is a quarter turn of the reading.
        let northeast = EarthRotation.planeAngle(of: SIMD2(1, -1))
        XCTAssertEqual(abs(northeast - east), .pi / 4, accuracy: 1e-12)
    }
}
