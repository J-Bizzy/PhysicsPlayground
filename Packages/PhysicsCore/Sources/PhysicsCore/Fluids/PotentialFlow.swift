//
//  PotentialFlow.swift
//  Exact ideal flow around a spinning cylinder: w(z) = U·ζ + U·a²/ζ − i·(Γ/2π)·ln ζ (stream + doublet + vortex, SI). Stagnation at sin θ = +Γ/(4πUa); Bernoulli integration recovers Kutta–Joukowski L′ = ρUΓ and zero drag (d'Alembert).
//  Signs: flow along +x, Γ counterclockwise-positive — positive Γ slows the top surface and lift points along −y.
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

    /// Bernoulli Cp = 1 − (v/U)²: 1 at stagnation, negative where flow beats the free stream.
    public func pressureCoefficient(at point: SIMD2<Double>) -> Double {
        let ratio = speed(at: point) / freeStreamSpeed
        return 1 - ratio * ratio
    }

    // MARK: Exact features

    /// Surface stagnation points, sin θ = Γ/(4πUa); empty when |Γ| > 4πUa lifts them off the surface.
    public func stagnationPoints() -> [SIMD2<Double>] {
        let s = circulation / (4 * .pi * freeStreamSpeed * radius)
        guard abs(s) <= 1 else { return [] }
        let theta = asin(s)
        return [theta, .pi - theta].map { angle in
            center + radius * SIMD2(cos(angle), sin(angle))
        }
    }

    /// Kutta–Joukowski lift per unit span = ρUΓ (N/m), along −y for counterclockwise Γ.
    public func liftPerSpan(airDensity: Double = 1.225) -> SIMD2<Double> {
        SIMD2(0, -airDensity * freeStreamSpeed * circulation)
    }

    /// Surface speed at angle θ from +x: |−2U·sinθ + Γ/(2πa)|.
    public func surfaceSpeed(atAngle theta: Double) -> Double {
        abs(-2 * freeStreamSpeed * sin(theta) + circulation / (2 * .pi * radius))
    }

    /// Net pressure force per unit span from integrating Bernoulli around the surface — the tests
    /// use it to VERIFY Kutta–Joukowski and d'Alembert rather than assume them.
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
