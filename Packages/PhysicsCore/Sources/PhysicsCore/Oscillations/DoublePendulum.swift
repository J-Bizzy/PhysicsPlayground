//
//  DoublePendulum.swift
//  PhysicsCore — planar double pendulum, exact Euler–Lagrange EOM by RK4.
//
//  PLANAR so the result has a closed form to be checked against (a 3-D
//  double pendulum has none). BOTH ANGLES ARE MEASURED FROM STRAIGHT DOWN
//  (the vertical, not the rod above) — the textbook convention; measuring
//  θ₂ relative to θ₁ gives an equivalent but different-looking system, the
//  classic way to get a pendulum that looks almost right. Chaos defeats a
//  reference-trajectory test, so the checks are what chaos leaves alone:
//  energy conservation, small-angle normal-mode frequencies, and reduction
//  to a simple pendulum as the lower mass vanishes.

import Foundation

/// Two masses, two rods, one plane.
public struct DoublePendulum: Equatable, Sendable {
    /// Angle of the upper rod from straight down, radians.
    public var theta1: Double
    /// Angle of the lower rod from straight down, radians.
    public var theta2: Double
    /// dθ₁/dt, rad/s.
    public var omega1: Double
    /// dθ₂/dt, rad/s.
    public var omega2: Double

    public init(theta1: Double, theta2: Double,
                omega1: Double = 0, omega2: Double = 0) {
        self.theta1 = theta1
        self.theta2 = theta2
        self.omega1 = omega1
        self.omega2 = omega2
    }

    /// The fixed properties of the rig.
    public struct Rig: Equatable, Sendable {
        public var length1: Double
        public var length2: Double
        public var mass1: Double
        public var mass2: Double
        /// Linear drag on each bob, N·s/m. Zero is the ideal
        /// energy-conserving system the energy test runs against.
        public var damping: Double

        public init(length1: Double, length2: Double,
                    mass1: Double, mass2: Double, damping: Double = 0) {
            self.length1 = length1
            self.length2 = length2
            self.mass1 = mass1
            self.mass2 = mass2
            self.damping = damping
        }
    }

    // MARK: The equations of motion

    /// Angular accelerations, exact.
    ///
    /// These are the standard closed forms; the shared denominator
    /// `L(2m₁ + m₂ − m₂cos(2θ₁ − 2θ₂))` is the determinant of the mass
    /// matrix and never vanishes for positive masses, which is why no
    /// singularity guard is needed beyond rejecting a degenerate rig.
    public static func acceleration(
        _ s: DoublePendulum, rig: Rig, gravity: Double
    ) -> (alpha1: Double, alpha2: Double) {
        let (l1, l2) = (rig.length1, rig.length2)
        let (m1, m2) = (rig.mass1, rig.mass2)
        let delta = s.theta1 - s.theta2
        let denominator = 2 * m1 + m2 - m2 * cos(2 * delta)
        guard l1 > 0, l2 > 0, m1 > 0, denominator != 0 else { return (0, 0) }

        let a1 = (-gravity * (2 * m1 + m2) * sin(s.theta1)
                  - m2 * gravity * sin(s.theta1 - 2 * s.theta2)
                  - 2 * sin(delta) * m2
                    * (s.omega2 * s.omega2 * l2
                       + s.omega1 * s.omega1 * l1 * cos(delta)))
            / (l1 * denominator)

        let a2 = (2 * sin(delta)
                  * (s.omega1 * s.omega1 * l1 * (m1 + m2)
                     + gravity * (m1 + m2) * cos(s.theta1)
                     + s.omega2 * s.omega2 * l2 * m2 * cos(delta)))
            / (l2 * denominator)

        // Damping enters as a torque opposing each bob's angular rate.
        // Kept OUT of the conservative terms above so the undamped case
        // is bit-for-bit the ideal system the energy test checks.
        guard rig.damping > 0 else { return (a1, a2) }
        return (a1 - rig.damping * s.omega1 / m1,
                a2 - rig.damping * s.omega2 / m2)
    }

    /// One RK4 step. RK4 (not Verlet) because the system is not separable:
    /// accelerations depend on BOTH angular velocities, so there is no
    /// position-only force for a kick-drift-kick.
    public static func step(_ s: DoublePendulum, dt: Double,
                            rig: Rig, gravity: Double) -> DoublePendulum {
        guard dt > 0 else { return s }

        func derivative(_ state: DoublePendulum) -> DoublePendulum {
            let a = acceleration(state, rig: rig, gravity: gravity)
            // A "derivative" reusing the state type: the θ slots carry
            // dθ/dt and the ω slots carry dω/dt.
            return DoublePendulum(theta1: state.omega1, theta2: state.omega2,
                                  omega1: a.alpha1, omega2: a.alpha2)
        }

        func advance(_ base: DoublePendulum, by d: DoublePendulum,
                     _ h: Double) -> DoublePendulum {
            DoublePendulum(theta1: base.theta1 + d.theta1 * h,
                           theta2: base.theta2 + d.theta2 * h,
                           omega1: base.omega1 + d.omega1 * h,
                           omega2: base.omega2 + d.omega2 * h)
        }

        let k1 = derivative(s)
        let k2 = derivative(advance(s, by: k1, dt / 2))
        let k3 = derivative(advance(s, by: k2, dt / 2))
        let k4 = derivative(advance(s, by: k3, dt))

        return DoublePendulum(
            theta1: s.theta1 + dt / 6 * (k1.theta1 + 2 * k2.theta1 + 2 * k3.theta1 + k4.theta1),
            theta2: s.theta2 + dt / 6 * (k1.theta2 + 2 * k2.theta2 + 2 * k3.theta2 + k4.theta2),
            omega1: s.omega1 + dt / 6 * (k1.omega1 + 2 * k2.omega1 + 2 * k3.omega1 + k4.omega1),
            omega2: s.omega2 + dt / 6 * (k1.omega2 + 2 * k2.omega2 + 2 * k3.omega2 + k4.omega2))
    }

    // MARK: What the state means

    /// Where the upper bob hangs, relative to the pivot. +x right, −y down.
    public func upperBob(rig: Rig) -> SIMD2<Double> {
        SIMD2(rig.length1 * sin(theta1), -rig.length1 * cos(theta1))
    }

    /// Where the lower bob hangs, relative to the pivot.
    public func lowerBob(rig: Rig) -> SIMD2<Double> {
        let upper = upperBob(rig: rig)
        return SIMD2(upper.x + rig.length2 * sin(theta2),
                     upper.y - rig.length2 * cos(theta2))
    }

    /// How fast the upper bob is moving, relative to the pivot.
    ///
    /// Differentiating `upperBob`: d/dt(L₁sinθ₁) = L₁ω₁cosθ₁, and
    /// d/dt(−L₁cosθ₁) = L₁ω₁sinθ₁.
    public func upperBobVelocity(rig: Rig) -> SIMD2<Double> {
        SIMD2(rig.length1 * omega1 * cos(theta1),
              rig.length1 * omega1 * sin(theta1))
    }

    /// How fast the lower bob is moving, relative to the pivot.
    public func lowerBobVelocity(rig: Rig) -> SIMD2<Double> {
        let upper = upperBobVelocity(rig: rig)
        return SIMD2(upper.x + rig.length2 * omega2 * cos(theta2),
                     upper.y + rig.length2 * omega2 * sin(theta2))
    }

    /// Total mechanical energy, J, with the pivot as the datum. The KE
    /// cross term `2L₁L₂θ₁'θ₂'cos(θ₁−θ₂)` is the coupling through which the
    /// rods trade energy; dropping it gives two independent pendulums.
    public func energy(rig: Rig, gravity: Double) -> Double {
        let (l1, l2) = (rig.length1, rig.length2)
        let (m1, m2) = (rig.mass1, rig.mass2)
        let kinetic = 0.5 * m1 * l1 * l1 * omega1 * omega1
            + 0.5 * m2 * (l1 * l1 * omega1 * omega1
                          + l2 * l2 * omega2 * omega2
                          + 2 * l1 * l2 * omega1 * omega2 * cos(theta1 - theta2))
        let potential = -(m1 + m2) * gravity * l1 * cos(theta1)
            - m2 * gravity * l2 * cos(theta2)
        return kinetic + potential
    }

    /// The two small-angle normal-mode angular frequencies, rad/s. For
    /// equal lengths and masses these are the textbook ω² = (2 ∓ √2)·g/L.
    /// A rig that cannot reproduce them has an error in the coupling term.
    public static func normalModeFrequencies(rig: Rig,
                                             gravity: Double) -> (Double, Double)? {
        let (l1, l2) = (rig.length1, rig.length2)
        let (m1, m2) = (rig.mass1, rig.mass2)
        guard l1 > 0, l2 > 0, m1 > 0, m2 >= 0, gravity > 0 else { return nil }
        // Linearised: M θ¨ = −K θ, with
        //   M = [[(m₁+m₂)l₁², m₂l₁l₂], [m₂l₁l₂, m₂l₂²]]
        //   K = [[(m₁+m₂)g l₁, 0], [0, m₂ g l₂]]
        // The generalised eigenproblem reduces to a quadratic in ω².
        let total = m1 + m2
        let a = total * l1 * l1 * m2 * l2 * l2 - m2 * m2 * l1 * l1 * l2 * l2
        let b = -(total * l1 * l1 * m2 * gravity * l2
                  + m2 * l2 * l2 * total * gravity * l1)
        let c = total * gravity * l1 * m2 * gravity * l2
        guard a != 0 else { return nil }
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        let w1 = (-b - root) / (2 * a)
        let w2 = (-b + root) / (2 * a)
        guard w1 > 0, w2 > 0 else { return nil }
        return (w1.squareRoot(), w2.squareRoot())
    }
}
