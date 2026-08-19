//
//  GaussSurface.swift
//  Flux quadrature for Gauss's law ∮E·dA = Q_enc/ε₀: open disc (polar quadrature) and closed sphere (equal-area Fibonacci patches, testable against the exact Q_enc/ε₀).
//

import Foundation
import simd

public enum GaussSurface {
    /// Vacuum permittivity, F/m.
    public static let epsilonZero = Constants.vacuumPermittivity

    /// Electric flux through a flat disc, N·m²/C — polar quadrature, area-weighted rings;
    /// exact for a uniform field at any resolution.
    public static func flux(
        throughDiscAt center: SIMD3<Double>,
        normal: SIMD3<Double>,
        radius: Double,
        charges: [PointCharge],
        radialSamples: Int = 12,
        angularSamples: Int = 24
    ) -> Double {
        guard radius > 0, radialSamples > 0, angularSamples > 0 else { return 0 }
        let n = simd_normalize(normal)
        let (u, v) = basis(perpendicularTo: n)
        var total = 0.0
        for ring in 0..<radialSamples {
            // Ring mid-point, weighted by the true annular area.
            let inner = radius * Double(ring) / Double(radialSamples)
            let outer = radius * Double(ring + 1) / Double(radialSamples)
            let r = (inner + outer) / 2
            let ringArea = .pi * (outer * outer - inner * inner)
            let patchArea = ringArea / Double(angularSamples)
            for step in 0..<angularSamples {
                let theta = 2 * .pi * (Double(step) + 0.5) / Double(angularSamples)
                let point = center + u * (r * cos(theta)) + v * (r * sin(theta))
                let field = ElectricField.vector(at: point, dueTo: charges)
                total += simd_dot(field, n) * patchArea
            }
        }
        return total
    }

    /// Outward flux through a closed sphere, N·m²/C — equal-area Fibonacci patches;
    /// on-surface charges are excluded by `enclosedCharge`'s strict interior test.
    public static func flux(
        throughSphereAt center: SIMD3<Double>,
        radius: Double,
        charges: [PointCharge],
        samples: Int = 2000
    ) -> Double {
        guard radius > 0, samples > 0 else { return 0 }
        let patchArea = 4 * .pi * radius * radius / Double(samples)
        var total = 0.0
        for direction in FieldLineTracer.fibonacciSphere(count: samples) {
            let point = center + direction * radius
            let field = ElectricField.vector(at: point, dueTo: charges)
            total += simd_dot(field, direction) * patchArea
        }
        return total
    }

    /// Charge strictly inside a sphere — the right-hand side of Gauss's law.
    public static func enclosedCharge(
        inSphereAt center: SIMD3<Double>,
        radius: Double,
        charges: [PointCharge]
    ) -> Double {
        charges
            .filter { simd_distance($0.position, center) < radius }
            .reduce(0) { $0 + $1.charge }
    }

    /// What Gauss's law predicts the closed-surface flux must be.
    public static func predictedFlux(
        inSphereAt center: SIMD3<Double>,
        radius: Double,
        charges: [PointCharge]
    ) -> Double {
        enclosedCharge(inSphereAt: center, radius: radius, charges: charges) / epsilonZero
    }

    /// Any two unit vectors completing `n` into a right-handed basis.
    static func basis(perpendicularTo n: SIMD3<Double>)
    -> (SIMD3<Double>, SIMD3<Double>) {
        // Helper = world axis least aligned with n, so the cross product is never near-degenerate.
        let helper: SIMD3<Double> = abs(n.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        let u = simd_normalize(simd_cross(helper, n))
        return (u, simd_cross(n, u))
    }
}
