//
//  TestChargeDynamics.swift
//  Probe-charge integration a = (q/m)·E(r): velocity-Verlet via ParticleDynamics, plus a Boris pusher for the full Lorentz force.
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

    /// Advances by `dt` split into `substeps` Verlet steps — accuracy independent of frame rate.
    public static func step(
        _ state: ProbeState,
        chargeToMassRatio: Double,
        dt: Double,
        substeps: Int,
        field: (SIMD3<Double>) -> SIMD3<Double>
    ) -> ProbeState {
        ParticleDynamics.step(state, dt: dt, substeps: substeps) { chargeToMassRatio * field($0) }
    }

    /// Full Lorentz force a = (q/m)(E + v×B) via the Boris pusher (half E kick, exact B rotation,
    /// half E kick) — a pure B field preserves |v| to machine precision, so cyclotron circles never spiral.
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
