//
//  NBody.swift
//  PhysicsCore — Gravitation
//
//  Newtonian n-body gravity: every pair attracts with F = G·m₁·m₂/r²,
//  integrated with velocity Verlet in kick–drift–kick form. Verlet is the
//  right integrator here — gravity is a conservative a(r) force, and the
//  symplectic property keeps orbital energy from drifting over thousands
//  of periods (naive Euler spirals outward; see the unit tests, which
//  pin energy drift and Kepler's third law).
//
//  A small softening length keeps close encounters finite before the
//  app-level collision/merge logic takes over.
//

import Foundation
import simd

public enum NBody {
    /// CODATA G, N·m²/kg².
    public static let gravitationalConstant = Constants.gravitational

    /// Minimum effective separation (m) — far smaller than any orbit we
    /// simulate, but keeps a near-overlap from producing infinite force.
    public static let softeningLength = 1e8

    // MARK: Forces

    /// Acceleration on every body from every other body.
    public static func accelerations(
        bodies: [CelestialBody],
        gravitationalConstant G: Double = gravitationalConstant
    ) -> [SIMD3<Double>] {
        var result = [SIMD3<Double>](repeating: .zero, count: bodies.count)
        guard bodies.count > 1 else { return result }
        for i in 0..<(bodies.count - 1) {
            for j in (i + 1)..<bodies.count {
                let offset = bodies[j].position - bodies[i].position
                let distanceSquared = max(simd_length_squared(offset),
                                          softeningLength * softeningLength)
                let inverseCube = 1 / (distanceSquared * distanceSquared.squareRoot())
                // a_i = G·m_j·r̂/r², computed as G·m_j·r/r³ (and mirrored).
                result[i] += (G * bodies[j].mass * inverseCube) * offset
                result[j] -= (G * bodies[i].mass * inverseCube) * offset
            }
        }
        return result
    }

    /// One velocity-Verlet (kick–drift–kick) step for the whole system.
    public static func step(
        bodies: inout [CelestialBody],
        dt: Double,
        gravitationalConstant G: Double = gravitationalConstant
    ) {
        let a0 = accelerations(bodies: bodies, gravitationalConstant: G)
        for i in bodies.indices {
            bodies[i].velocity += (dt / 2) * a0[i]
            bodies[i].position += dt * bodies[i].velocity
        }
        let a1 = accelerations(bodies: bodies, gravitationalConstant: G)
        for i in bodies.indices {
            bodies[i].velocity += (dt / 2) * a1[i]
        }
    }

    // MARK: Energies

    public static func kineticEnergy(of body: CelestialBody) -> Double {
        0.5 * body.mass * simd_length_squared(body.velocity)
    }

    /// Gravitational potential energy of one body against all others
    /// (zero reference at infinity, so bound orbits have negative totals).
    public static func potentialEnergy(
        of index: Int,
        in bodies: [CelestialBody],
        gravitationalConstant G: Double = gravitationalConstant
    ) -> Double {
        var energy = 0.0
        for j in bodies.indices where j != index {
            let distance = max(simd_distance(bodies[index].position, bodies[j].position),
                               softeningLength)
            energy -= G * bodies[index].mass * bodies[j].mass / distance
        }
        return energy
    }

    /// Total system energy: ΣKE + pairwise PE (each pair counted once).
    public static func totalEnergy(
        bodies: [CelestialBody],
        gravitationalConstant G: Double = gravitationalConstant
    ) -> Double {
        var energy = bodies.reduce(0) { $0 + kineticEnergy(of: $1) }
        for i in 0..<max(bodies.count - 1, 0) {
            for j in (i + 1)..<bodies.count {
                let distance = max(simd_distance(bodies[i].position, bodies[j].position),
                                   softeningLength)
                energy -= G * bodies[i].mass * bodies[j].mass / distance
            }
        }
        return energy
    }

    // MARK: Two-body orbit math (planet vs. a dominant central mass)

    /// μ = G(M + m) — the parameter every two-body formula is actually
    /// written in terms of.
    ///
    /// The textbook shorthand μ = GM quietly assumes m ≪ M, which is fine
    /// for a spacecraft and not fine for Jupiter: dropping the planet's
    /// own mass shifts its period by about 0.05 %. More to the point,
    /// mixing the two conventions inside one readout makes a body's
    /// semi-major axis and its period describe slightly different orbits,
    /// which is exactly the kind of error that hides forever because both
    /// numbers look right.
    public static func standardGravitationalParameter(
        primaryMass: Double, bodyMass: Double = 0,
        gravitationalConstant G: Double = gravitationalConstant
    ) -> Double {
        G * (primaryMass + bodyMass)
    }

    /// v_circ = √(GM/r)
    public static func circularOrbitSpeed(
        centralMass: Double, distance: Double,
        gravitationalConstant G: Double = gravitationalConstant
    ) -> Double {
        (G * centralMass / distance).squareRoot()
    }

    /// v_esc = √(2GM/r) — exactly √2 × circular speed.
    public static func escapeSpeed(
        centralMass: Double, distance: Double,
        gravitationalConstant G: Double = gravitationalConstant
    ) -> Double {
        (2 * G * centralMass / distance).squareRoot()
    }

    /// Semi-major axis from the vis-viva equation: a = 1/(2/r − v²/μ).
    /// nil when the orbit is unbound (v ≥ escape speed).
    public static func semiMajorAxis(
        distance: Double, speed: Double, centralMass: Double,
        gravitationalConstant G: Double = gravitationalConstant
    ) -> Double? {
        let mu = G * centralMass
        let inverse = 2 / distance - speed * speed / mu
        guard inverse > 0 else { return nil }
        return 1 / inverse
    }

    /// Kepler's third law: T = 2π√(a³/GM).
    public static func orbitalPeriod(
        semiMajorAxis a: Double, centralMass: Double,
        gravitationalConstant G: Double = gravitationalConstant
    ) -> Double {
        2 * .pi * (a * a * a / (G * centralMass)).squareRoot()
    }

    // MARK: Collisions

    /// Perfectly inelastic merge: total mass, momentum-conserving velocity,
    /// mass-weighted position, volume-additive radius, heavier body's name.
    public static func merged(_ a: CelestialBody, _ b: CelestialBody) -> CelestialBody {
        let mass = a.mass + b.mass
        let heavier = a.mass >= b.mass ? a : b
        return CelestialBody(
            name: heavier.name,
            mass: mass,
            radius: cbrt(a.radius * a.radius * a.radius + b.radius * b.radius * b.radius),
            position: (a.mass * a.position + b.mass * b.position) / mass,
            velocity: (a.mass * a.velocity + b.mass * b.velocity) / mass
        )
    }

    // MARK: Prediction

    /// The path one body will trace through a frozen-rule copy of the
    /// system (everything simulates forward together; nothing is actually
    /// mutated). Powers the "orbit you'd get if you let go now" preview.
    public static func predictedPath(
        bodies: [CelestialBody],
        of index: Int,
        dt: Double,
        steps: Int,
        pointStride: Int = 4,
        gravitationalConstant G: Double = gravitationalConstant
    ) -> [SIMD3<Double>] {
        guard bodies.indices.contains(index) else { return [] }
        var clone = bodies
        var points = [clone[index].position]
        points.reserveCapacity(steps / pointStride + 2)
        for step in 1...steps {
            Self.step(bodies: &clone, dt: dt, gravitationalConstant: G)
            if step % pointStride == 0 {
                points.append(clone[index].position)
            }
        }
        return points
    }
}
