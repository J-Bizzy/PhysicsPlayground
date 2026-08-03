//
//  DipoleDynamics.swift
//  PhysicsCore — Magnetism
//
//  A bar magnet with MASS AND ROTATIONAL INERTIA, moving under the exact
//  dipole force and torque.
//
//  WHY THIS EXISTS. `MagneticField` has always returned the true dipole
//  B, force and torque — it even swaps in a finite two-pole bar where a
//  point dipole would be wrong near the poles. But the bench moved its
//  magnets by a MOBILITY law: velocity proportional to force, angular
//  rate proportional to torque, both capped by tuned gains. Exact
//  fields, quasi-static motion. The consequence is one specific thing a
//  magnetism lab is expected to show and this one could not:
//
//      A NEEDLE RELEASED AT AN ANGLE SWINGS PAST NORTH AND RINGS BACK.
//
//  Nothing without inertia can overshoot. The mobility bench slides into
//  alignment and stops, which looks plausible and is not what a compass
//  does.
//
//  THE MASS IS DERIVED, NOT INVENTED, and that is the part that makes
//  this honest rather than a second set of tuned constants. A permanent
//  magnet's moment is its saturation magnetisation times its volume:
//
//      m = M_s · V        so    V = m / M_s
//
//  With M_s ≈ 1.0 × 10⁶ A/m for sintered NdFeB and a bar of fixed
//  length, that fixes the cross-section, hence the radius, hence — with
//  the alloy's density — the mass and the moment of inertia. So a
//  magnet you make stronger genuinely becomes a bigger, heavier bar,
//  which is why it also becomes slower to turn. Nothing here is free to
//  be tuned for feel.
//
//  Transverse moment of inertia of a uniform cylinder about its centre:
//
//      I = m(3r² + L²)/12
//
//  and for these proportions the L² term carries ~99.9 % of it, which is
//  the same statement as "a bar magnet is a rod".
//
//  DAMPING IS REAL AND IS DISCLOSED. A magnet in air does eventually
//  stop, and one in a lab demo stops in a few swings rather than a few
//  minutes, so the damping here is stronger than air alone — the same
//  licence a lab takes by mounting a needle on a jewelled pivot with a
//  drop of oil. It is a linear drag on both velocity and angular
//  velocity, it removes energy and can never add it, and its coefficient
//  is the ONE tunable number in this file.
//
//  Integration is semi-implicit (symplectic) Euler, substepped — the
//  same scheme `ElasticSheet` uses and for the same reason: the torque
//  depends on orientation, the damping on velocity, and a symplectic
//  step stays stable without pretending to be higher order than it is.
//

import Foundation
import simd

/// One bar magnet's inertial state: where it is, how fast it is going,
/// and how fast it is turning.
public struct DipoleBody: Sendable, Equatable {
    public var velocity: SIMD3<Double>
    /// Angular velocity, rad/s. Its direction is the rotation axis.
    public var angularVelocity: SIMD3<Double>

    public init(velocity: SIMD3<Double> = .zero,
                angularVelocity: SIMD3<Double> = .zero) {
        self.velocity = velocity
        self.angularVelocity = angularVelocity
    }
}

public enum DipoleDynamics {

    // MARK: The bar, derived from its moment

    /// Saturation magnetisation of sintered NdFeB, A/m. A magnet's
    /// moment divided by this is the volume of material it takes.
    public static let saturationMagnetisation = 1.0e6

    /// Density of sintered NdFeB, kg/m³.
    public static let alloyDensity = 7500.0

    /// The volume a magnet of this moment must have, m³.
    public static func volume(moment: Double) -> Double {
        max(abs(moment), 1e-9) / saturationMagnetisation
    }

    /// Mass of a bar of this moment, kg. Independent of its length —
    /// the material is what weighs.
    public static func mass(moment: Double) -> Double {
        volume(moment: moment) * alloyDensity
    }

    /// Radius of a cylindrical bar of this moment and length, m.
    public static func radius(moment: Double, length: Double) -> Double {
        sqrt(volume(moment: moment) / (Double.pi * max(length, 1e-6)))
    }

    /// Transverse moment of inertia about the bar's centre, kg·m².
    ///
    /// I = m(3r² + L²)/12 — a uniform cylinder about a diameter through
    /// its middle, which is the axis a needle swings about.
    public static func momentOfInertia(moment: Double, length: Double) -> Double {
        let m = mass(moment: moment)
        let r = radius(moment: moment, length: length)
        return m * (3 * r * r + length * length) / 12
    }

    // MARK: The step

    /// Advances one magnet by `dt` under a force and a torque.
    ///
    /// - Parameters:
    ///   - damping: linear drag coefficient, 1/s. Applied to both the
    ///     velocity and the angular velocity. Removes energy only.
    ///
    /// Semi-implicit Euler: accelerate first, then move with the NEW
    /// velocity. That ordering is what keeps an oscillator's energy
    /// bounded instead of growing, and it is why this is stable at a
    /// frame step where explicit Euler would wind up.
    public static func step(
        body: inout DipoleBody,
        position: inout SIMD3<Double>,
        moment: inout SIMD3<Double>,
        force: SIMD3<Double>,
        torque: SIMD3<Double>,
        mass: Double,
        momentOfInertia: Double,
        damping: Double,
        dt: Double
    ) {
        guard dt > 0, mass > 0, momentOfInertia > 0 else { return }

        body.velocity += (force / mass) * dt
        body.angularVelocity += (torque / momentOfInertia) * dt

        // Drag. Written as a decay factor rather than −γv·dt so it
        // cannot overshoot into negative velocity at a large step, which
        // is the one way a linear drag can inject energy.
        let decay = exp(-damping * dt)
        body.velocity *= decay
        body.angularVelocity *= decay

        position += body.velocity * dt

        // Rotate the moment by ω dt about ω̂. The magnitude of `moment`
        // is a property of the magnet and must survive exactly, so this
        // is a rotation rather than an addition — and it is renormalised
        // against the drift a long run would otherwise accumulate.
        let rate = simd_length(body.angularVelocity)
        if rate > 1e-12 {
            let strength = simd_length(moment)
            let q = simd_quatd(angle: rate * dt, axis: body.angularVelocity / rate)
            let turned = q.act(moment)
            let turnedLength = simd_length(turned)
            moment = turnedLength > 1e-18
                ? turned * (strength / turnedLength) : moment
        }
    }

    // MARK: What the tests recover

    /// Small-oscillation period of a magnet of moment `momentMagnitude`
    /// in a uniform field, s — the classic magnetometer formula.
    ///
    ///     T = 2π √( I / (m B) )
    ///
    /// Nothing in `step` is told this. It is what integrating τ = m × B
    /// through a real inertia produces, and recovering it from a
    /// simulated swing is how the tests check the dynamics rather than
    /// the arithmetic.
    public static func smallOscillationPeriod(
        momentMagnitude: Double, fieldMagnitude: Double, momentOfInertia: Double
    ) -> Double {
        guard momentMagnitude > 0, fieldMagnitude > 0, momentOfInertia > 0 else {
            return .infinity
        }
        return 2 * Double.pi
            * sqrt(momentOfInertia / (momentMagnitude * fieldMagnitude))
    }
}
