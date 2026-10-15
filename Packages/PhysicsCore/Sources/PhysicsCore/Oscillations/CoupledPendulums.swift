//
//  CoupledPendulums.swift
//  PhysicsCore — Oscillations
//
//  Two pendulums whose bobs are joined by a spring. Each bob moves on the
//  sphere its cable allows, in full 3-D, under gravity, the spring and
//  (optionally) air; the spring is Hooke's law between the two bobs.
//
//  Released from one bob alone, the swing passes to the other and back:
//  the two normal modes (in step, ω₁ = √(g/L); against each other,
//  ω₂ = √(g/L + 2k/m)) beat, and the energy sloshes with period
//  2π/(ω₂ − ω₁). Swung across the spring instead of along it, they barely
//  talk: an unstretched spring has no sideways stiffness to first order.
//
//  Integrated with RATTLE: velocity Verlet whose position step is pulled
//  back onto each cable's sphere along the constraint's own gradient
//  (SHAKE) and whose velocity is then made tangent to it. The scheme is
//  symplectic and time-reversible, so the energy wanders by O(dt²) and
//  never drifts. The single pendulum's trick of resetting the speed from
//  the work-energy theorem cannot be used here: a spring moves energy
//  between the bobs, which is the whole point.
//
//  SI units. Positions are bob relative to its own pivot.
//

import Foundation
import simd

public struct CoupledPendulums: Sendable, Equatable {
    /// The two bobs, each relative to its own pivot.
    public var a: SphericalPendulum
    public var b: SphericalPendulum

    public init(a: SphericalPendulum, b: SphericalPendulum) {
        self.a = a
        self.b = b
    }

    public struct Rig: Sendable, Equatable {
        public var pivotA: SIMD3<Double>
        public var pivotB: SIMD3<Double>
        public var lengthA: Double
        public var lengthB: Double
        public var massA: Double
        public var massB: Double
        /// Spring constant, N/m.
        public var stiffness: Double
        /// The spring's natural length, m.
        public var restLength: Double
        /// Linear drag on each bob, N·s/m.
        public var dampingA: Double
        public var dampingB: Double

        public init(pivotA: SIMD3<Double>, pivotB: SIMD3<Double>,
                    lengthA: Double, lengthB: Double, massA: Double, massB: Double,
                    stiffness: Double, restLength: Double,
                    dampingA: Double = 0, dampingB: Double = 0) {
            self.pivotA = pivotA
            self.pivotB = pivotB
            self.lengthA = lengthA
            self.lengthB = lengthB
            self.massA = massA
            self.massB = massB
            self.stiffness = stiffness
            self.restLength = restLength
            self.dampingA = dampingA
            self.dampingB = dampingB
        }
    }

    /// The spring's pull on bob A (bob B feels the opposite): toward B when
    /// stretched, away when compressed.
    public static func springForceOnA(bobA: SIMD3<Double>, bobB: SIMD3<Double>,
                                      stiffness: Double, restLength: Double) -> SIMD3<Double> {
        let d = bobB - bobA
        let length = simd_length(d)
        guard length > 1e-12 else { return .zero }
        return stiffness * (length - restLength) * (d / length)
    }

    /// The world positions of the two bobs.
    public func bobs(rig: Rig) -> (a: SIMD3<Double>, b: SIMD3<Double>) {
        (rig.pivotA + a.position, rig.pivotB + b.position)
    }

    /// One RATTLE step. A held bob is the hand's: it does not move, but its
    /// spring still pulls on the other.
    public static func step(_ state: CoupledPendulums, dt: Double, rig: Rig, gravity: Double,
                            heldA: Bool = false, heldB: Bool = false) -> CoupledPendulums {
        guard dt > 0 else { return state }
        let g = SIMD3<Double>(0, -gravity, 0)

        func accelerations(_ s: CoupledPendulums, velocities: (SIMD3<Double>, SIMD3<Double>))
            -> (SIMD3<Double>, SIMD3<Double>) {
            let bobs = s.bobs(rig: rig)
            let spring = springForceOnA(bobA: bobs.a, bobB: bobs.b,
                                        stiffness: rig.stiffness, restLength: rig.restLength)
            let accelerationA = g + (spring - rig.dampingA * velocities.0) / rig.massA
            let accelerationB = g + (-spring - rig.dampingB * velocities.1) / rig.massB
            return (accelerationA, accelerationB)
        }

        /// Pulls an unconstrained step back onto the sphere of radius `length`
        /// along the constraint's gradient at the start of the step (SHAKE):
        /// x = x̃ + μ x₀, with |x| = L. Returns x and the half-step velocity
        /// consistent with it.
        func shake(_ start: SIMD3<Double>, _ halfVelocity: SIMD3<Double>,
                   length: Double) -> (SIMD3<Double>, SIMD3<Double>) {
            let free = start + dt * halfVelocity
            let a = simd_length_squared(start)
            let b = 2 * simd_dot(free, start)
            let c = simd_length_squared(free) - length * length
            let discriminant = max(b * b - 4 * a * c, 0)
            // The root nearest zero: the smallest correction that lands on the sphere.
            let root = discriminant.squareRoot()
            let mu1 = (-b + root) / (2 * a), mu2 = (-b - root) / (2 * a)
            let mu = abs(mu1) < abs(mu2) ? mu1 : mu2
            let position = free + mu * start
            return (position, halfVelocity + mu * start / dt)
        }

        /// Makes a velocity tangent to the sphere at `position` (RATTLE's
        /// second half): the cable allows no radial speed.
        func tangent(_ velocity: SIMD3<Double>, at position: SIMD3<Double>) -> SIMD3<Double> {
            velocity - simd_dot(velocity, position) / simd_length_squared(position) * position
        }

        var next = state
        let start = accelerations(state, velocities: (state.a.velocity, state.b.velocity))
        var halfA = state.a.velocity + 0.5 * dt * start.0
        var halfB = state.b.velocity + 0.5 * dt * start.1
        if heldA {
            halfA = .zero
        } else {
            (next.a.position, halfA) = shake(state.a.position, halfA, length: rig.lengthA)
        }
        if heldB {
            halfB = .zero
        } else {
            (next.b.position, halfB) = shake(state.b.position, halfB, length: rig.lengthB)
        }
        let end = accelerations(next, velocities: (halfA, halfB))
        next.a.velocity = heldA ? .zero : tangent(halfA + 0.5 * dt * end.0, at: next.a.position)
        next.b.velocity = heldB ? .zero : tangent(halfB + 0.5 * dt * end.1, at: next.b.position)
        return next
    }

    // MARK: Energy and forces

    /// Kinetic energy of each bob, and the potential of the whole system
    /// (gravity measured from each bob's lowest point, plus the spring).
    public func energies(rig: Rig, gravity: Double)
        -> (kineticA: Double, kineticB: Double, potential: Double) {
        let kineticA = 0.5 * rig.massA * simd_length_squared(a.velocity)
        let kineticB = 0.5 * rig.massB * simd_length_squared(b.velocity)
        let bobs = self.bobs(rig: rig)
        let stretch = simd_distance(bobs.a, bobs.b) - rig.restLength
        let potential = rig.massA * gravity * (a.position.y + rig.lengthA)
            + rig.massB * gravity * (b.position.y + rig.lengthB)
            + 0.5 * rig.stiffness * stretch * stretch
        return (kineticA, kineticB, potential)
    }

    public func totalEnergy(rig: Rig, gravity: Double) -> Double {
        let e = energies(rig: rig, gravity: gravity)
        return e.kineticA + e.kineticB + e.potential
    }

    /// Each cable's tension, from the radial balance on its bob:
    /// T = m(v²/L + g cos θ) + F_spring · r̂.
    public func tensions(rig: Rig, gravity: Double) -> (a: Double, b: Double) {
        let bobs = self.bobs(rig: rig)
        let spring = Self.springForceOnA(bobA: bobs.a, bobB: bobs.b,
                                         stiffness: rig.stiffness, restLength: rig.restLength)
        func tension(_ bob: SphericalPendulum, length: Double, mass: Double,
                     springForce: SIMD3<Double>) -> Double {
            let radial = bob.position / length
            let cosTheta = -radial.y
            return mass * (simd_length_squared(bob.velocity) / length + gravity * cosTheta)
                + simd_dot(springForce, radial)
        }
        return (tension(a, length: rig.lengthA, mass: rig.massA, springForce: spring),
                tension(b, length: rig.lengthB, mass: rig.massB, springForce: -spring))
    }

    // MARK: Closed forms

    /// The two normal modes of identical pendulums (length L, mass m) joined
    /// by a spring of stiffness k: swinging together, the spring never
    /// stretches; swinging apart, it adds 2k/m.
    public static func normalModes(length: Double, mass: Double, stiffness: Double,
                                   gravity: Double) -> (inPhase: Double, antiPhase: Double) {
        ((gravity / length).squareRoot(), (gravity / length + 2 * stiffness / mass).squareRoot())
    }

    /// How long the swing takes to pass from one bob to the other and back:
    /// the beat of the two modes, 2π/(ω₂ − ω₁).
    public static func beatPeriod(length: Double, mass: Double, stiffness: Double,
                                  gravity: Double) -> Double {
        let modes = normalModes(length: length, mass: mass, stiffness: stiffness, gravity: gravity)
        return 2 * .pi / (modes.antiPhase - modes.inPhase)
    }
}
