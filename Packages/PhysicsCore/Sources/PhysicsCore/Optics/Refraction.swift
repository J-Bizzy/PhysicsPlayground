//
//  Refraction.swift
//  PhysicsCore — Optics
//
//  Real refraction: Snell's law in vector form, total internal
//  reflection, and Cauchy dispersion — the physics the ideal thin-lens
//  bench deliberately skips. sin θ₁ · n₁ = sin θ₂ · n₂ is implemented
//  once, exactly, on direction vectors; everything the studio shows
//  (bending, TIR, rainbows out of prisms) falls out of it.
//

import Foundation
import simd

public enum Refraction {
    /// Refracts a unit `direction` crossing a surface whose unit
    /// `normal` points toward the incoming side (against the ray),
    /// from index `n1` into `n2`. Returns nil on total internal
    /// reflection — beyond the critical angle there is no transmitted
    /// ray at all, not a dim one.
    public static func refract(
        direction: SIMD3<Double>, normal: SIMD3<Double>,
        n1: Double, n2: Double
    ) -> SIMD3<Double>? {
        let d = simd_normalize(direction)
        let n = simd_normalize(normal)
        let eta = n1 / n2
        let cosIncident = -simd_dot(d, n)
        let sinTransmittedSquared = eta * eta * max(0, 1 - cosIncident * cosIncident)
        guard sinTransmittedSquared <= 1 else { return nil }
        let cosTransmitted = (1 - sinTransmittedSquared).squareRoot()
        return simd_normalize(eta * d + (eta * cosIncident - cosTransmitted) * n)
    }

    /// Mirror reflection: the angle of incidence equals the angle of
    /// reflection because the tangential component survives untouched.
    public static func reflect(
        direction: SIMD3<Double>, normal: SIMD3<Double>
    ) -> SIMD3<Double> {
        let d = simd_normalize(direction)
        let n = simd_normalize(normal)
        return simd_normalize(d - 2 * simd_dot(d, n) * n)
    }

    /// The critical angle for light heading from the denser medium
    /// (n1) toward the rarer one (n2 < n1): past this, TIR.
    public static func criticalAngle(n1: Double, n2: Double) -> Double? {
        guard n1 > n2, n1 > 0 else { return nil }
        return asin(n2 / n1)
    }

    /// Cauchy dispersion for crown glass: n(λ) = A + B/λ². Blue light
    /// sees a higher index than red — the entire reason prisms make
    /// rainbows. λ in nanometers; B in nm².
    public static func cauchyIndex(
        wavelengthNanometers: Double,
        a: Double = 1.5046, b: Double = 4200
    ) -> Double {
        a + b / (wavelengthNanometers * wavelengthNanometers)
    }
}
