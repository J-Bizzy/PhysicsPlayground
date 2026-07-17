//
//  Oscillations.swift
//  PhysicsCore — Oscillations
//
//  The dynamics behind the Pendulums and Springs modules.
//
//  · SphericalPendulum — a bob constrained to a sphere around its
//    pivot, integrated with velocity-Verlet + constraint projection.
//    Fully nonlinear (no small-angle shortcut), stable indefinitely,
//    and genuinely 3D: a sideways throw precesses like the real thing,
//    while planar starts stay planar and match the classic analytics.
//  · SpringOscillator — Hooke's law with viscous damping via RK4.
//  · CoupledSprings — two masses, three springs; energy sloshes
//    between the masses as beats, straight out of the equations.
//
//  SI units throughout. No RealityKit here, ever.
//

import Foundation
import simd

// MARK: - Spherical pendulum

public struct SphericalPendulum: Sendable, Equatable {
    /// Bob position relative to the pivot, m (|position| == length).
    public var position: SIMD3<Double>
    /// Bob velocity, m/s (tangent to the constraint sphere).
    public var velocity: SIMD3<Double>

    public init(position: SIMD3<Double>, velocity: SIMD3<Double> = .zero) {
        self.position = position
        self.velocity = velocity
    }

    /// A planar start: hanging angle θ from vertical, at rest.
    public init(length: Double, angle: Double) {
        position = SIMD3(length * sin(angle), -length * cos(angle), 0)
        velocity = .zero
    }

    /// Angle from straight-down vertical, rad.
    public func angle(length: Double) -> Double {
        acos(min(max(-position.y / length, -1), 1))
    }

    /// One step of velocity-Verlet with projection back onto the
    /// constraint sphere — the standard stable way to keep a cable taut
    /// forever without spring hacks or drift. `damping` is a linear
    /// drag coefficient (N·s/m) against the bob's velocity.
    public static func step(
        _ state: SphericalPendulum, dt: Double,
        length: Double, gravity: Double, mass: Double, damping: Double
    ) -> SphericalPendulum {
        guard dt > 0, length > 0, mass > 0 else { return state }
        var s = state

        func acceleration(_ p: SIMD3<Double>, _ v: SIMD3<Double>) -> SIMD3<Double> {
            var a = SIMD3(0.0, -gravity, 0.0) - (damping / mass) * v
            // Remove the radial component: the cable supplies exactly the
            // tension that keeps |p| fixed; the centripetal part is
            // handled by the projection itself.
            let radial = simd_normalize(p)
            a -= simd_dot(a, radial) * radial
            return a
        }

        let a0 = acceleration(s.position, s.velocity)
        var newPosition = s.position + s.velocity * dt + 0.5 * a0 * dt * dt
        // Project the position back to the sphere (taut cable).
        newPosition = simd_normalize(newPosition) * length

        // Direction from the Verlet velocity update, projected tangent…
        let a1 = acceleration(newPosition, s.velocity)
        var newVelocity = s.velocity + 0.5 * (a0 + a1) * dt
        let radial = simd_normalize(newPosition)
        newVelocity -= simd_dot(newVelocity, radial) * radial

        // …but the SPEED comes from the work-energy theorem: the cable's
        // tension does no work, so ΔKE = −mg·Δh − drag work, exactly.
        // This pins energy conservation to machine precision when
        // undamped — the energy bars hold rock steady.
        let dragWork = 2 * (damping / mass) * simd_length_squared(s.velocity) * dt
        let speedSquared = simd_length_squared(s.velocity)
            - 2 * gravity * (newPosition.y - s.position.y)
            - dragWork
        let directionLength = simd_length(newVelocity)
        if directionLength > 1e-12, speedSquared > 0 {
            newVelocity = newVelocity / directionLength * speedSquared.squareRoot()
        } else if speedSquared <= 0 {
            newVelocity = .zero
        }

        s.position = newPosition
        s.velocity = newVelocity
        return s
    }

    /// Kinetic and potential energy (PE zero at the lowest point).
    public func energies(length: Double, gravity: Double, mass: Double)
    -> (kinetic: Double, potential: Double) {
        let kinetic = 0.5 * mass * simd_length_squared(velocity)
        let potential = mass * gravity * (position.y + length)
        return (kinetic, potential)
    }

    /// Cable tension magnitude, N: T = m(g cosθ + v²/L).
    public func tension(length: Double, gravity: Double, mass: Double) -> Double {
        let cosTheta = min(max(-position.y / length, -1), 1)
        return mass * (gravity * cosTheta + simd_length_squared(velocity) / length)
    }

    /// Small-angle period 2π√(L/g) — the analytic touchstone.
    public static func smallAnglePeriod(length: Double, gravity: Double) -> Double {
        2 * .pi * (length / gravity).squareRoot()
    }
}

// MARK: - Single spring

public struct SpringOscillator: Sendable, Equatable {
    /// Displacement from the natural length, m (+ = stretched).
    public var displacement: Double
    public var velocity: Double

    public init(displacement: Double, velocity: Double = 0) {
        self.displacement = displacement
        self.velocity = velocity
    }

    /// a = (−kx − cv + F_bias)/m, RK4. `biasForce` carries gravity when
    /// the apparatus hangs it along the motion axis (shifts equilibrium,
    /// exactly as in the real lab).
    public static func step(
        _ state: SpringOscillator, dt: Double,
        stiffness: Double, mass: Double, damping: Double, biasForce: Double = 0
    ) -> SpringOscillator {
        guard dt > 0, mass > 0 else { return state }
        func f(_ x: Double, _ v: Double) -> (dx: Double, dv: Double) {
            (v, (-stiffness * x - damping * v + biasForce) / mass)
        }
        let s = state
        let k1 = f(s.displacement, s.velocity)
        let k2 = f(s.displacement + 0.5 * dt * k1.dx, s.velocity + 0.5 * dt * k1.dv)
        let k3 = f(s.displacement + 0.5 * dt * k2.dx, s.velocity + 0.5 * dt * k2.dv)
        let k4 = f(s.displacement + dt * k3.dx, s.velocity + dt * k3.dv)
        return SpringOscillator(
            displacement: s.displacement + dt / 6 * (k1.dx + 2 * k2.dx + 2 * k3.dx + k4.dx),
            velocity: s.velocity + dt / 6 * (k1.dv + 2 * k2.dv + 2 * k3.dv + k4.dv)
        )
    }

    public func energies(stiffness: Double, mass: Double)
    -> (kinetic: Double, potential: Double) {
        (0.5 * mass * velocity * velocity,
         0.5 * stiffness * displacement * displacement)
    }

    public static func period(stiffness: Double, mass: Double) -> Double {
        2 * .pi * (mass / stiffness).squareRoot()
    }
}

// MARK: - Coupled oscillators (two masses, three springs)

public struct CoupledSprings: Sendable, Equatable {
    /// Displacements of the two masses from their rest positions, m.
    public var displacements: SIMD2<Double>
    public var velocities: SIMD2<Double>

    public init(displacements: SIMD2<Double>, velocities: SIMD2<Double> = .zero) {
        self.displacements = displacements
        self.velocities = velocities
    }

    /// Wall—k—m1—kCoupling—m2—k—wall, viscous damping c on each mass.
    /// RK4 on the 4-dimensional state.
    public static func step(
        _ state: CoupledSprings, dt: Double,
        stiffness: Double, coupling: Double, masses: SIMD2<Double>, damping: Double
    ) -> CoupledSprings {
        guard dt > 0, masses.x > 0, masses.y > 0 else { return state }
        func accel(_ x: SIMD2<Double>, _ v: SIMD2<Double>) -> SIMD2<Double> {
            let middle = coupling * (x.y - x.x)
            return SIMD2(
                (-stiffness * x.x + middle - damping * v.x) / masses.x,
                (-stiffness * x.y - middle - damping * v.y) / masses.y
            )
        }
        let s = state
        let a1 = accel(s.displacements, s.velocities)
        let x2 = s.displacements + 0.5 * dt * s.velocities
        let v2 = s.velocities + 0.5 * dt * a1
        let a2 = accel(x2, v2)
        let x3 = s.displacements + 0.5 * dt * v2
        let v3 = s.velocities + 0.5 * dt * a2
        let a3 = accel(x3, v3)
        let x4 = s.displacements + dt * v3
        let v4 = s.velocities + dt * a3
        let a4 = accel(x4, v4)
        let sixth: Double = dt / 6
        var velocitySum: SIMD2<Double> = s.velocities + v4
        velocitySum += 2 * v2
        velocitySum += 2 * v3
        var accelSum: SIMD2<Double> = a1 + a4
        accelSum += 2 * a2
        accelSum += 2 * a3
        return CoupledSprings(
            displacements: s.displacements + sixth * velocitySum,
            velocities: s.velocities + sixth * accelSum
        )
    }

    /// Per-mass mechanical energy (kinetic + share of adjacent springs)
    /// — the quantity that visibly sloshes between the masses.
    public func massEnergies(stiffness: Double, coupling: Double, masses: SIMD2<Double>)
    -> SIMD2<Double> {
        let stretch: Double = displacements.y - displacements.x
        let couplingHalf: Double = 0.25 * coupling * stretch * stretch
        let kinetic1: Double = 0.5 * masses.x * velocities.x * velocities.x
        let kinetic2: Double = 0.5 * masses.y * velocities.y * velocities.y
        let spring1: Double = 0.5 * stiffness * displacements.x * displacements.x
        let spring2: Double = 0.5 * stiffness * displacements.y * displacements.y
        return SIMD2(kinetic1 + spring1 + couplingHalf,
                     kinetic2 + spring2 + couplingHalf)
    }
}
