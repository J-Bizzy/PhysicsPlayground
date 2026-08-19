//  Induction.swift — Faraday's law, ε = −N dΦ/dt. Flux is numeric (ring sampling of B·n̂;
//  magnets move freely, no closed form for an arbitrary pose); the coaxial-dipole closed
//  form is kept as the tests' measuring stick, not the implementation.

import Foundation
import simd

public enum Induction {
    /// Magnetic flux through a disc, Wb: Σ B·n̂ dA over concentric-ring samples. Exact as
    /// sampling tightens; the default 12×24 grid is within ~1% of the closed form at coil scale.
    public static func flux(throughDiscAt center: SIMD3<Double>,
                            normal: SIMD3<Double>,
                            radius: Double,
                            magnets: [BarMagnet],
                            rings: Int = 12,
                            spokes: Int = 24) -> Double {
        guard radius > 0, !magnets.isEmpty else { return 0 }
        let n = simd_normalize(normal)
        let seed = abs(n.x) < 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
        let u = simd_normalize(simd_cross(n, seed))
        let v = simd_cross(n, u)

        let ringWidth = radius / Double(rings)
        var total = 0.0
        for ring in 0..<rings {
            let r = radius * (Double(ring) + 0.5) / Double(rings)
            let area = 2 * .pi * r * ringWidth / Double(spokes)
            for spoke in 0..<spokes {
                let angle = 2 * .pi * Double(spoke) / Double(spokes)
                let point = center + u * (r * cos(angle)) + v * (r * sin(angle))
                total += simd_dot(MagneticField.vector(at: point, dueTo: magnets), n) * area
            }
        }
        return total
    }

    /// Closed form the numeric integral must recover — coaxial dipole:
    /// Φ = μ₀mR²/(2(R²+z²)^{3/2}), with μ₀/2 = 2π×10⁻⁷.
    public static func axialDipoleFlux(moment: Double,
                                       distance z: Double,
                                       discRadius R: Double) -> Double {
        (2 * .pi * 1e-7) * moment * R * R / pow(R * R + z * z, 1.5)
    }

    /// Faraday's law by finite difference: ε = −N ΔΦ/Δt.
    public static func emf(turns: Int,
                           fluxNow: Double, fluxBefore: Double,
                           dt: Double) -> Double {
        guard dt > 1e-9 else { return 0 }
        return -Double(turns) * (fluxNow - fluxBefore) / dt
    }
}
