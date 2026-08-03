//
//  PotentialFlow.swift
//  PhysicsCore — Fluids
//
//  Ideal (inviscid, incompressible, irrotational) flow around a spinning
//  cylinder — the classical exactly-solvable wind tunnel. The velocity
//  field is the derivative of the complex potential
//
//      w(z) = U·ζ + U·a²/ζ − i·(Γ/2π)·ln ζ,   ζ = z − center
//
//  (uniform stream + doublet + vortex), evaluated exactly — no CFD, no
//  grids. Everything the module teaches falls out analytically:
//
//    · no penetration: the surface is a streamline (tested to 1e-9),
//    · the top of a non-spinning cylinder moves at exactly 2U,
//    · stagnation points sit where sin θ = +Γ/(4πUa) — the sign this
//      file's own `stagnationAngles` and `surfaceSpeed` use, and the
//      one its Kutta–Joukowski convention requires. The header carried
//      a minus until 2026-08-03; the code was self-consistent and the
//      summary was the outlier,
//    · Bernoulli gives the surface pressure, and integrating it recovers
//      the Kutta–Joukowski lift L' = ρUΓ and exactly zero drag —
//      d'Alembert's paradox, which the module states rather than hides.
//
//  Sign conventions: flow along +x, Γ positive counterclockwise, so
//  positive Γ slows the top surface and lift points along −y.
//

import Foundation
import simd

public struct CylinderFlow: Equatable, Sendable {
    /// Free-stream speed U along +x, m/s.
    public var freeStreamSpeed: Double
    public var center: SIMD2<Double>
    /// Cylinder radius a, m.
    public var radius: Double
    /// Circulation Γ, m²/s, counterclockwise-positive.
    public var circulation: Double

    public init(freeStreamSpeed: Double, center: SIMD2<Double> = .zero,
                radius: Double, circulation: Double = 0) {
        self.freeStreamSpeed = freeStreamSpeed
        self.center = center
        self.radius = radius
        self.circulation = circulation
    }

    // MARK: Complex helpers (SIMD2 as x + iy)

    private static func multiply(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)
    }

    private static func reciprocal(_ z: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(z.x, -z.y) / simd_length_squared(z)
    }

    // MARK: Velocity field

    /// Flow velocity at `point`; zero inside the cylinder.
    public func velocity(at point: SIMD2<Double>) -> SIMD2<Double> {
        let zeta = point - center
        let distanceSquared = simd_length_squared(zeta)
        guard distanceSquared >= radius * radius else { return .zero }

        // dw/dz = U − U·a²/ζ² − i·(Γ/2π)/ζ ;  velocity = conjugate(dw/dz).
        let inverse = Self.reciprocal(zeta)
        let inverseSquared = Self.multiply(inverse, inverse)
        var derivative = SIMD2<Double>(freeStreamSpeed, 0)
        derivative -= freeStreamSpeed * radius * radius * inverseSquared
        derivative -= Self.multiply(SIMD2(0, circulation / (2 * .pi)), inverse)
        return SIMD2(derivative.x, -derivative.y)
    }

    public func speed(at point: SIMD2<Double>) -> Double {
        simd_length(velocity(at: point))
    }

    /// Bernoulli pressure coefficient Cp = 1 − (v/U)². 1 at stagnation,
    /// negative wherever the flow is faster than the free stream.
    public func pressureCoefficient(at point: SIMD2<Double>) -> Double {
        let ratio = speed(at: point) / freeStreamSpeed
        return 1 - ratio * ratio
    }

    // MARK: Exact features

    /// The surface stagnation points, where the flow comes to rest:
    /// sin θ = Γ/(4πUa) (they climb toward the slowed top surface as
    /// counterclockwise spin grows). Empty when the spin is strong enough
    /// (|Γ| > 4πUa) to lift the stagnation point off the surface.
    public func stagnationPoints() -> [SIMD2<Double>] {
        let s = circulation / (4 * .pi * freeStreamSpeed * radius)
        guard abs(s) <= 1 else { return [] }
        let theta = asin(s)
        return [theta, .pi - theta].map { angle in
            center + radius * SIMD2(cos(angle), sin(angle))
        }
    }

    /// Kutta–Joukowski: lift per unit span = ρUΓ, directed along −y for
    /// counterclockwise Γ (the spinning top surface moves against the
    /// stream, slows the flow, and raises the pressure there).
    public func liftPerSpan(airDensity: Double = 1.225) -> SIMD2<Double> {
        SIMD2(0, -airDensity * freeStreamSpeed * circulation)
    }

    /// Surface flow speed at angle θ (from +x): |−2U·sinθ + Γ/(2πa)| —
    /// the counterclockwise vortex opposes the stream over the top.
    public func surfaceSpeed(atAngle theta: Double) -> Double {
        abs(-2 * freeStreamSpeed * sin(theta) + circulation / (2 * .pi * radius))
    }

    /// Net pressure force per unit span from integrating Bernoulli around
    /// the surface — used by the tests to *verify* Kutta–Joukowski and
    /// d'Alembert rather than assume them.
    public func integratedPressureForce(airDensity: Double = 1.225, samples: Int = 3600) -> SIMD2<Double> {
        var force = SIMD2<Double>.zero
        let dTheta = 2 * .pi / Double(samples)
        for index in 0..<samples {
            let theta = Double(index) * dTheta
            let v = surfaceSpeed(atAngle: theta)
            let pressure = 0.5 * airDensity
                * (freeStreamSpeed * freeStreamSpeed - v * v)
            let normal = SIMD2(cos(theta), sin(theta))
            force -= pressure * normal * radius * dTheta
        }
        return force
    }
}
