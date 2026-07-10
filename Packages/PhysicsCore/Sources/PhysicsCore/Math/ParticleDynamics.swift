//
//  ParticleDynamics.swift
//  PhysicsCore — Math
//
//  Domain-agnostic particle kinematics: velocity Verlet over an arbitrary
//  acceleration field a(r). Every simulation that moves a particle under a
//  position-dependent conservative force uses this one integrator —
//  electrostatics passes (q/m)·E(r), orbital mechanics passes Σ Gm·r̂/r².
//
//  Velocity Verlet is the standard symplectic scheme for conservative
//  forces. Per step:
//      v(t+½h) = v(t) + ½h·a(r(t))
//      r(t+h)  = r(t) + h·v(t+½h)
//      v(t+h)  = v(t+½h) + ½h·a(r(t+h))
//  Unlike naive Euler it doesn't systematically pump energy into the orbit,
//  so trajectories stay physically plausible over many frames.
//
//  NOTE: not suitable for velocity-dependent forces (e.g. magnetic v×B) —
//  the magnetism module uses a Boris pusher instead.
//

import Foundation
import simd

public enum ParticleDynamics {
    public struct State: Equatable, Sendable {
        public var position: SIMD3<Double>
        public var velocity: SIMD3<Double>

        public init(position: SIMD3<Double>, velocity: SIMD3<Double> = .zero) {
            self.position = position
            self.velocity = velocity
        }
    }

    /// Advances the particle by one velocity-Verlet step of length `dt`.
    public static func step(
        _ state: State,
        dt: Double,
        acceleration: (SIMD3<Double>) -> SIMD3<Double>
    ) -> State {
        let a0 = acceleration(state.position)
        let halfStepVelocity = state.velocity + (dt / 2) * a0
        let newPosition = state.position + dt * halfStepVelocity
        let a1 = acceleration(newPosition)
        let newVelocity = halfStepVelocity + (dt / 2) * a1
        return State(position: newPosition, velocity: newVelocity)
    }

    /// Advances by `dt` split into `substeps` Verlet steps — call this per
    /// rendered frame so accuracy doesn't depend on the display frame rate.
    public static func step(
        _ state: State,
        dt: Double,
        substeps: Int,
        acceleration: (SIMD3<Double>) -> SIMD3<Double>
    ) -> State {
        let h = dt / Double(substeps)
        var current = state
        for _ in 0..<substeps {
            current = step(current, dt: h, acceleration: acceleration)
        }
        return current
    }
}
