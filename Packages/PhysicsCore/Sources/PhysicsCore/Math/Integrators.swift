//
//  Integrators.swift
//  PhysicsCore — Math: RK4 over (position, velocity). Handles a(r, v) forces
//  (drag) that Verlet cannot; exact for constant acceleration.
//

import Foundation
import simd

public enum Integrators {
    /// One classical RK4 step of the coupled ODE r′ = v, v′ = a(r, v).
    public static func rk4Step(
        _ state: ParticleDynamics.State,
        dt: Double,
        acceleration: (SIMD3<Double>, SIMD3<Double>) -> SIMD3<Double>
    ) -> ParticleDynamics.State {
        let r0 = state.position
        let v0 = state.velocity
        let half = dt / 2

        let a1 = acceleration(r0, v0)
        let k1r = v0

        let k2r = v0 + half * a1
        let a2 = acceleration(r0 + half * k1r, k2r)

        let k3r = v0 + half * a2
        let a3 = acceleration(r0 + half * k2r, k3r)

        let k4r = v0 + dt * a3
        let a4 = acceleration(r0 + dt * k3r, k4r)

        var positionSlope = k1r + k4r
        positionSlope += 2 * k2r
        positionSlope += 2 * k3r
        var velocitySlope = a1 + a4
        velocitySlope += 2 * a2
        velocitySlope += 2 * a3

        return ParticleDynamics.State(
            position: r0 + (dt / 6) * positionSlope,
            velocity: v0 + (dt / 6) * velocitySlope
        )
    }
}
