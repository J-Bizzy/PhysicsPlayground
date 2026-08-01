//
//  Foucault.swift
//  PhysicsCore — Oscillations
//
//  Earth's rotation, as the pendulum feels it.
//
//  A pendulum swinging in a rotating frame picks up the Coriolis
//  acceleration −2Ω × v, and the consequence is the one Foucault hung
//  under the Panthéon dome in 1851: the swing plane holds still against
//  the STARS while the ground turns underneath, so from the room it
//  appears to rotate at Ω sin φ. At the pole that is one full turn per
//  sidereal day; at the equator it is nothing at all.
//
//  WHY THIS LIVES IN THIS MODULE. `SphericalPendulum` has been fully
//  three-dimensional since it was written — no small-angle shortcut, a
//  real constraint sphere — and nothing in the app needed the third
//  dimension for anything. A planar pendulum would have rendered
//  everything Pendulums showed. Foucault is the physics that makes the
//  sphere necessary.
//
//  Ω enters as a VECTOR rather than as a latitude, so this file states
//  the mechanics and the app states the geography. That also means the
//  integrator is exact for any Ω a caller cares to hand it, including an
//  exaggerated one — see the disclosure note on `angularVelocity`.
//

import Foundation
import simd

/// Earth's spin, and what a pendulum standing on it does about it.
public enum EarthRotation: Sendable {

    /// The sidereal day, s: one turn relative to the fixed stars.
    ///
    /// NOT 86 400. The solar day is longer because Earth has also moved
    /// along its orbit and has to turn a little further to face the Sun
    /// again. The pendulum's plane is fixed against the STARS, so the
    /// sidereal day is the one that governs it — using 86 400 here would
    /// put the polar precession period out by about four minutes, which
    /// is small, wrong, and exactly the sort of thing this project's
    /// whole claim rests on not doing.
    public static let siderealDay: Double = 86_164.0905

    /// Ω = 2π / sidereal day ≈ 7.292 × 10⁻⁵ rad/s.
    public static let angularSpeed: Double = 2 * .pi / siderealDay

    /// Earth's angular velocity in the local lab frame, rad/s.
    ///
    /// Frame convention, matching the app's rooms: **+x east, +y up,
    /// +z south**. North is −z, so
    ///
    ///     Ω = Ω(cos φ · N̂ + sin φ · Û) = Ω(0, sin φ, −cos φ)
    ///
    /// - Parameter spin: a multiplier on Earth's real rate, for making
    ///   the effect watchable. **This is an exaggeration and every caller
    ///   that uses it above 1 must disclose it**, alongside the true
    ///   rate. Earth turns the plane 7.6° per hour at 45°, which is real,
    ///   correct, and far too slow to stand and watch.
    ///
    ///   The exaggeration is honest in a way a faked one would not be:
    ///   raising `spin` is exactly equivalent to standing on a planet
    ///   that spins faster, and every number below stays the true
    ///   consequence of the Ω actually being integrated.
    public static func angularVelocity(latitudeDegrees: Double,
                                       spin: Double = 1) -> SIMD3<Double> {
        let phi = latitudeDegrees * .pi / 180
        return angularSpeed * spin * SIMD3(0, sin(phi), -cos(phi))
    }

    /// The rate at which the swing plane appears to turn, rad/s.
    ///
    /// **Ω sin φ — the sine law, and the whole point.** Only the
    /// VERTICAL component of Ω precesses the plane; the horizontal
    /// component's effect averages away over a swing. Positive means
    /// clockwise seen from above, which is the northern hemisphere.
    public static func precessionRate(latitudeDegrees: Double,
                                      spin: Double = 1) -> Double {
        let phi = latitudeDegrees * .pi / 180
        return angularSpeed * spin * sin(phi)
    }

    /// How long the plane takes to come back around, s.
    ///
    /// `nil` on the equator, where it never does — and that is a real
    /// answer rather than a missing one, so callers must say so out loud
    /// instead of printing an enormous number.
    public static func precessionPeriod(latitudeDegrees: Double,
                                        spin: Double = 1) -> Double? {
        let rate = precessionRate(latitudeDegrees: latitudeDegrees, spin: spin)
        guard abs(rate) > 1e-15 else { return nil }
        return 2 * .pi / abs(rate)
    }

    /// Latitudes worth standing at, including the two that make the law
    /// visible by being its endpoints.
    public struct Site: Sendable, Equatable, Identifiable {
        public let name: String
        public let latitudeDegrees: Double
        public var id: String { name }

        public init(name: String, latitudeDegrees: Double) {
            self.name = name
            self.latitudeDegrees = latitudeDegrees
        }
    }

    /// The Panthéon is where Foucault hung his in 1851; the other three
    /// are the endpoints and the midpoint of the sine.
    public static let sites: [Site] = [
        Site(name: "Equator", latitudeDegrees: 0),
        Site(name: "Paris", latitudeDegrees: 48.8462),
        Site(name: "Pole", latitudeDegrees: 90),
    ]

    /// The angle of a swing plane in the horizontal plane, rad.
    ///
    /// Measured from +x (east) toward −z (north), and folded onto a HALF
    /// turn: a pendulum swinging east–west and one swinging west–east are
    /// the same plane, so the natural period of this quantity is π and
    /// not 2π. Callers unwrapping it must step by π.
    public static func planeAngle(of horizontal: SIMD2<Double>) -> Double {
        // atan2 over the doubled angle keeps this continuous through the
        // fold; halving brings it back. Straight atan2 would jump by π
        // every half swing, which is a discontinuity in the READING
        // rather than in the physics.
        let doubled = atan2(2 * horizontal.x * (-horizontal.y),
                            horizontal.x * horizontal.x - horizontal.y * horizontal.y)
        return doubled / 2
    }
}
