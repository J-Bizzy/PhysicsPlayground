//  NBody.swift — Newtonian n-body gravity by a fourth-order symmetric symplectic composition
//  (PEFRL): time-reversible, energy does not drift, and an isolated two-body orbit does not
//  precess numerically (tests pin drift, Kepler III and the apsidal drift per orbit). A per-body
//  softening radius keeps a close encounter finite, and the potential matches the force inside it.

import Foundation
import simd

public enum NBody {
    /// CODATA G, N·m²/kg².
    public static let gravitationalConstant = Constants.gravitational

    /// Default effective separation floor for a pair, m. A caller may pass a
    /// per-body softening radius instead; the pair's floor is then s_i + s_j.
    public static let softeningLength = 1e8

    /// The PEFRL coefficients (Omelyan, Mryglod & Folk, Comput. Phys. Commun.
    /// 146, 2002): a palindromic drift–kick composition with four force
    /// evaluations per step. Fourth order, so a Kepler orbit's spurious
    /// apsidal drift is ~10⁻⁵ of leapfrog's at the same step.
    public enum Composition {
        public static let xi = 0.1786178958448091
        public static let lambda = -0.2123418310626054
        public static let chi = -0.06626458266981849
    }

    // MARK: Forces

    /// The pair's separation floor: the sum of the two bodies' softening
    /// radii, or the house floor when none are given.
    @inline(__always)
    private static func pairFloor(_ softening: [Double]?, _ i: Int, _ j: Int) -> Double {
        guard let softening else { return softeningLength }
        return softening[i] + softening[j]
    }

    /// Acceleration on every body from every other body. Inside a pair's
    /// floor ε the force falls linearly to zero at the centre, as it does
    /// inside a uniform sphere — finite, and matched by `potentialEnergy`.
    public static func accelerations(
        bodies: [CelestialBody],
        gravitationalConstant G: Double = gravitationalConstant,
        softening: [Double]? = nil
    ) -> [SIMD3<Double>] {
        var result = [SIMD3<Double>](repeating: .zero, count: bodies.count)
        guard bodies.count > 1 else { return result }
        for i in 0..<(bodies.count - 1) {
            for j in (i + 1)..<bodies.count {
                let offset = bodies[j].position - bodies[i].position
                let floor = pairFloor(softening, i, j)
                let distanceSquared = max(simd_length_squared(offset), floor * floor)
                let inverseCube = 1 / (distanceSquared * distanceSquared.squareRoot())
                result[i] += (G * bodies[j].mass * inverseCube) * offset
                result[j] -= (G * bodies[i].mass * inverseCube) * offset
            }
        }
        return result
    }

    /// One PEFRL step for the whole system. `frozen` bodies attract but do
    /// not move (a body held in a hand); `softening` is one radius per body.
    /// The composition is symmetric, so a negative `dt` retraces the step.
    public static func step(
        bodies: inout [CelestialBody],
        dt: Double,
        gravitationalConstant G: Double = gravitationalConstant,
        softening: [Double]? = nil,
        frozen: [Bool]? = nil
    ) {
        @inline(__always) func moves(_ i: Int) -> Bool { !(frozen?[i] ?? false) }
        func drift(_ fraction: Double) {
            let c = fraction * dt
            for i in bodies.indices where moves(i) {
                bodies[i].position += c * bodies[i].velocity
            }
        }
        func kick(_ fraction: Double) {
            let c = fraction * dt
            let a = accelerations(bodies: bodies, gravitationalConstant: G, softening: softening)
            for i in bodies.indices where moves(i) {
                bodies[i].velocity += c * a[i]
            }
        }
        let xi = Composition.xi, lambda = Composition.lambda, chi = Composition.chi
        drift(xi)
        kick((1 - 2 * lambda) / 2)
        drift(chi)
        kick(lambda)
        drift(1 - 2 * (chi + xi))
        kick(lambda)
        drift(chi)
        kick((1 - 2 * lambda) / 2)
        drift(xi)
    }

    // MARK: Energies

    public static func kineticEnergy(of body: CelestialBody) -> Double {
        0.5 * body.mass * simd_length_squared(body.velocity)
    }

    /// The potential of one pair, matching `accelerations` exactly: −Gm₁m₂/r
    /// outside the floor ε, the uniform-sphere interior −Gm₁m₂(3ε² − r²)/(2ε³)
    /// inside it — continuous with a continuous derivative at ε.
    public static func pairPotential(
        _ a: CelestialBody, _ b: CelestialBody, floor: Double,
        gravitationalConstant G: Double = gravitationalConstant
    ) -> Double {
        let r = simd_distance(a.position, b.position)
        guard r < floor else { return -G * a.mass * b.mass / r }
        return -G * a.mass * b.mass * (3 * floor * floor - r * r) / (2 * floor * floor * floor)
    }

    /// PE of one body against all others; zero at infinity, so bound totals are negative.
    public static func potentialEnergy(
        of index: Int,
        in bodies: [CelestialBody],
        gravitationalConstant G: Double = gravitationalConstant,
        softening: [Double]? = nil
    ) -> Double {
        var energy = 0.0
        for j in bodies.indices where j != index {
            energy += pairPotential(bodies[index], bodies[j],
                                    floor: pairFloor(softening, index, j),
                                    gravitationalConstant: G)
        }
        return energy
    }

    /// Total system energy: ΣKE + pairwise PE (each pair counted once).
    public static func totalEnergy(
        bodies: [CelestialBody],
        gravitationalConstant G: Double = gravitationalConstant,
        softening: [Double]? = nil
    ) -> Double {
        var energy = bodies.reduce(0) { $0 + kineticEnergy(of: $1) }
        for i in 0..<max(bodies.count - 1, 0) {
            for j in (i + 1)..<bodies.count {
                energy += pairPotential(bodies[i], bodies[j],
                                        floor: pairFloor(softening, i, j),
                                        gravitationalConstant: G)
            }
        }
        return energy
    }

    /// Σ m·v — zero in the barycentric frame; the integrator conserves it
    /// exactly (frozen bodies excepted: a hand is an external force).
    public static func momentum(of bodies: [CelestialBody]) -> SIMD3<Double> {
        bodies.reduce(SIMD3<Double>.zero) { $0 + $1.mass * $1.velocity }
    }

    /// The mass-weighted centre, or zero for an empty system.
    public static func barycentre(of bodies: [CelestialBody]) -> SIMD3<Double> {
        let mass = bodies.reduce(0) { $0 + $1.mass }
        guard mass > 0 else { return .zero }
        return bodies.reduce(SIMD3<Double>.zero) { $0 + $1.mass * $1.position } / mass
    }

    // MARK: Two-body orbit math (planet vs. a dominant central mass)

    /// μ = G(M + m), m³/s² — not the shorthand GM: dropping m shifts Jupiter's period ~0.05%,
    /// and mixing the two conventions makes a and T describe different orbits in one readout.
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

    /// Vis-viva: a = 1/(2/r − v²/μ); nil when unbound (v ≥ escape speed).
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

    /// Perfectly inelastic merge: momentum-conserving velocity, mass-weighted position, volume-additive radius, heavier body's name.
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

    /// Path one body traces through a cloned system (nothing mutated) — the "orbit if you let go
    /// now" preview. Takes the live system's softening and frozen bodies so it follows the same law.
    public static func predictedPath(
        bodies: [CelestialBody],
        of index: Int,
        dt: Double,
        steps: Int,
        pointStride: Int = 4,
        gravitationalConstant G: Double = gravitationalConstant,
        softening: [Double]? = nil,
        frozen: [Bool]? = nil
    ) -> [SIMD3<Double>] {
        guard bodies.indices.contains(index) else { return [] }
        var clone = bodies
        var points = [clone[index].position]
        points.reserveCapacity(steps / pointStride + 2)
        for step in 1...steps {
            Self.step(bodies: &clone, dt: dt, gravitationalConstant: G,
                      softening: softening, frozen: frozen)
            if step % pointStride == 0 {
                points.append(clone[index].position)
            }
        }
        return points
    }
}
