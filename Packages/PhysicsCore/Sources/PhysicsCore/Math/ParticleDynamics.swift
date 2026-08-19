//
//  ParticleDynamics.swift
//  PhysicsCore — Math: velocity Verlet over an arbitrary a(r) field —
//  symplectic, energy-stable for conservative forces. NOT suitable for
//  velocity-dependent forces (v×B); magnetism uses a Boris pusher.
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
