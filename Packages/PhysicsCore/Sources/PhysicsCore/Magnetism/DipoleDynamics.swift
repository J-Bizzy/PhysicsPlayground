//  DipoleDynamics.swift — a bar magnet with mass and rotational inertia, so a released
//  needle overshoots north and rings back (a mobility law cannot overshoot).
//
//  The mass is DERIVED, not tuned: m = M_s·V (NdFeB M_s ≈ 1e6 A/m) fixes volume from
//  moment, hence radius, mass, and I = m(3r²+L²)/12 — a stronger magnet is genuinely a
//  heavier bar. Damping (linear drag, removes energy only, stronger than air as a lab
//  pivot is) is the ONE tunable number. Integration: semi-implicit (symplectic) Euler,
//  substepped, as in ElasticSheet.

import Foundation
import simd

/// One bar magnet's inertial state: velocity and angular velocity.
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

    /// Saturation magnetisation of sintered NdFeB, A/m: moment / this = material volume.
    public static let saturationMagnetisation = 1.0e6

    /// Density of sintered NdFeB, kg/m³.
    public static let alloyDensity = 7500.0

    /// The volume a magnet of this moment must have, m³.
    public static func volume(moment: Double) -> Double {
        max(abs(moment), 1e-9) / saturationMagnetisation
    }

    /// Mass of a bar of this moment, kg — independent of length; the material is what weighs.
    public static func mass(moment: Double) -> Double {
        volume(moment: moment) * alloyDensity
    }

    /// Radius of a cylindrical bar of this moment and length, m.
    public static func radius(moment: Double, length: Double) -> Double {
        sqrt(volume(moment: moment) / (Double.pi * max(length, 1e-6)))
    }

    /// Transverse moment of inertia about the bar's centre, kg·m²: I = m(3r² + L²)/12 —
    /// uniform cylinder about a mid-diameter, the axis a needle swings about.
    public static func momentOfInertia(moment: Double, length: Double) -> Double {
        let m = mass(moment: moment)
        let r = radius(moment: moment, length: length)
        return m * (3 * r * r + length * length) / 12
    }

    // MARK: The step

    /// Advances one magnet by `dt`. `damping`: linear drag, 1/s, on v and ω; removes energy only.
    /// Semi-implicit Euler — accelerate first, move with the NEW velocity: that ordering keeps
    /// an oscillator's energy bounded where explicit Euler winds up.
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

        // Drag as a decay factor, not −γv·dt: cannot overshoot into negative velocity
        // at a large step — the one way a linear drag can inject energy.
        let decay = exp(-damping * dt)
        body.velocity *= decay
        body.angularVelocity *= decay

        position += body.velocity * dt

        // Rotate the moment by ω·dt about ω̂ — a rotation, not an addition, so |moment|
        // survives exactly; renormalised against long-run drift.
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

    /// Small-oscillation period in a uniform field, s: T = 2π√(I/(mB)). `step` is never
    /// told this — recovering it from a simulated swing is how the tests check the dynamics.
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
