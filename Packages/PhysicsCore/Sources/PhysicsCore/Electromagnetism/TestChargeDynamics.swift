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
}
