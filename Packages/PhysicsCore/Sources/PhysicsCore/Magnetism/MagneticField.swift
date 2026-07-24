//
//  MagneticField.swift
//  PhysicsCore — Magnetism
//
//  The exact ideal-dipole field, and the dipole–dipole force and torque
//  that make two magnets attract, repel, and snap into alignment. Pure
//  functions the renderer and model only ever *ask* — physics lives here.
//
//  Dipole field:  B(r) = (μ₀/4π)[ 3(m·r̂)r̂ − m ] / r³
//  Torque:        τ = m × B          (turns a magnet to align with B)
//  Dipole force:  F = (3μ₀/4π r⁴)[ (m₁·r̂)m₂ + (m₂·r̂)m₁
//                                    + (m₁·m₂)r̂ − 5(m₁·r̂)(m₂·r̂)r̂ ]
//

import Foundation
import simd

public enum MagneticField {
    /// μ₀/4π in T·m/A.
    public static let mu0over4pi = 1e-7
    /// Separations below this (m) are treated as "at the dipole," where
    /// the 1/r³ field is singular — return zero and let the renderer hide it.
    public static let singularityRadius = 1e-4

    // MARK: Field

    /// B at `point` from a single dipole.
    public static func vector(at point: SIMD3<Double>, dueTo magnet: BarMagnet) -> SIMD3<Double> {
        let r = point - magnet.position
        let d2 = simd_length_squared(r)
        guard d2 > singularityRadius * singularityRadius else { return .zero }
        let d = d2.squareRoot()
        let rHat = r / d
        let m = magnet.moment
        return mu0over4pi * (3 * simd_dot(m, rHat) * rHat - m) / (d2 * d)
    }

    /// B at `point` from any number of magnets, by superposition.
    public static func vector(at point: SIMD3<Double>, dueTo magnets: [BarMagnet]) -> SIMD3<Double> {
        magnets.reduce(.zero) { $0 + vector(at: point, dueTo: $1) }
    }

    /// Field strength |B| in tesla — a convenience for display.
    public static func magnitude(at point: SIMD3<Double>, dueTo magnets: [BarMagnet]) -> Double {
        simd_length(vector(at: point, dueTo: magnets))
    }

    // MARK: Force & torque

    /// Force on dipole `b` from dipole `a`'s field. Obeys Newton's third
    /// law: force(on: b, dueTo: a) == −force(on: a, dueTo: b).
    public static func force(on b: BarMagnet, dueTo a: BarMagnet) -> SIMD3<Double> {
        let r = b.position - a.position
        let d2 = simd_length_squared(r)
        guard d2 > singularityRadius * singularityRadius else { return .zero }
        let d = d2.squareRoot()
        let rHat = r / d
        let m1 = a.moment, m2 = b.moment
        let m1r = simd_dot(m1, rHat), m2r = simd_dot(m2, rHat), m1m2 = simd_dot(m1, m2)
        let coeff = 3 * mu0over4pi / (d2 * d2)
        return coeff * (m1r * m2 + m2r * m1 + m1m2 * rHat - 5 * m1r * m2r * rHat)
    }

    /// Net force on `b` from all the `others`.
    public static func netForce(on b: BarMagnet, from others: [BarMagnet]) -> SIMD3<Double> {
        others.reduce(.zero) { $0 + force(on: b, dueTo: $1) }
    }

    /// Torque on `b` in the combined field of the `others`: τ = m × B.
    /// It's zero when the moment is parallel to the local field and
    /// maximal when perpendicular — the drive that aligns a compass.
    public static func torque(on b: BarMagnet, inFieldOf others: [BarMagnet]) -> SIMD3<Double> {
        simd_cross(b.moment, vector(at: b.position, dueTo: others))
    }

    /// Interaction energy of dipole `b` in dipole `a`'s field: U = −m_b·B_a.
    /// Lowest (most negative) when they attract head-to-tail.
    public static func potentialEnergy(of b: BarMagnet, in a: BarMagnet) -> Double {
        -simd_dot(b.moment, vector(at: b.position, dueTo: a))
    }
}
