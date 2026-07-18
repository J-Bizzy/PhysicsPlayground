//
//  TestChargeDynamics.swift
//  PhysicsCore — Electromagnetism
//
//  Electrostatics flavor of the shared velocity-Verlet integrator: the
//  acceleration of a probe charge is a = (q/m)·E(r), so this wrapper takes
//  the charge-to-mass ratio and an E-field closure and delegates the actual
//  stepping to Math's ParticleDynamics.
//

import Foundation
import simd

public enum TestChargeDynamics {
    public typealias ProbeState = ParticleDynamics.State

    /// Advances the probe by one velocity-Verlet step of length `dt`.
    /// `chargeToMassRatio` is q/m in C/kg; `field` returns E in N/C.
    public static func step(
        _ state: ProbeState,
        chargeToMassRatio: Double,
        dt: Double,
        field: (SIMD3<Double>) -> SIMD3<Double>
    ) -> ProbeState {
        ParticleDynamics.step(state, dt: dt) { chargeToMassRatio * field($0) }
    }

    /// Advances by `dt` split into `substeps` Verlet steps — call this per
    /// rendered frame so accuracy doesn't depend on the display frame rate.
    public static func step(
        _ state: ProbeState,
        chargeToMassRatio: Double,
        dt: Double,
        substeps: Int,
        field: (SIMD3<Double>) -> SIMD3<Double>
    ) -> ProbeState {
        ParticleDynamics.step(state, dt: dt, substeps: substeps) { chargeToMassRatio * field($0) }
    }

    /// Full Lorentz force a = (q/m)(E + v×B) via the Boris pusher —
    /// the standard plasma-physics integrator: half an electric kick,
    /// an exact magnetic rotation, half an electric kick. A pure
    /// magnetic field rotates the velocity WITHOUT changing its
    /// magnitude, to machine precision, so cyclotron circles never
    /// spiral artificially.
    public static func stepLorentz(
        _ state: ProbeState,
        chargeToMassRatio: Double,
        dt: Double,
        substeps: Int,
        electricField: (SIMD3<Double>) -> SIMD3<Double>,
        magneticField: SIMD3<Double>
    ) -> ProbeState {
        var s = state
        let h = dt / Double(max(substeps, 1))
        for _ in 0..<max(substeps, 1) {
            let electricKick = chargeToMassRatio * electricField(s.position) * (h / 2)
            var v = s.velocity + electricKick
            let t = chargeToMassRatio * magneticField * (h / 2)
            let tSquared = simd_length_squared(t)
            let scale = 2 / (1 + tSquared)
            let vPrime = v + simd_cross(v, t)
            v += simd_cross(vPrime, t) * scale
            v += electricKick
            s.velocity = v
            s.position += v * h
        }
        return s
    }
}
