//
//  ElectricField.swift
//  Coulomb's Law and superposition as pure functions (SI) — the renderer only asks this layer, never computes physics itself.
//

import Foundation
import simd

public enum ElectricField {
    /// Coulomb constant k = 1/(4πε₀), N·m²/C² — derived from ε₀ in `Constants`, never typed by hand.
    public static let k = Constants.coulomb

    /// Below this separation (m) the 1/r² field is singular: return zero and let the renderer hide it.
    public static let singularityRadius = 1e-6

    /// E at `point` from one point charge (N/C): E = k·q/r²·r̂, computed as k·q·r/|r|³.
    public static func vector(at point: SIMD3<Double>, dueTo charge: PointCharge) -> SIMD3<Double> {
        let r = point - charge.position
        let distanceSquared = simd_length_squared(r)
        guard distanceSquared > singularityRadius * singularityRadius else {
            return .zero
        }
        let distance = distanceSquared.squareRoot()
        return (k * charge.charge / (distanceSquared * distance)) * r
    }

    /// E at `point` from any number of charges, by vector superposition.
    public static func vector(at point: SIMD3<Double>, dueTo charges: [PointCharge]) -> SIMD3<Double> {
        charges.reduce(.zero) { total, charge in
            total + vector(at: point, dueTo: charge)
        }
    }

    /// E at `point` from every charge except the one at `index` — allocation-free
    /// (called per charge per frame; `MagneticField` has the twin).
    public static func vector(at point: SIMD3<Double>,
                              dueTo charges: [PointCharge],
                              excluding index: Int) -> SIMD3<Double> {
        var sum = SIMD3<Double>.zero
        for i in charges.indices where i != index {
            sum += vector(at: point, dueTo: charges[i])
        }
        return sum
    }

    /// Field magnitude in N/C at `point` — a convenience for display code.
    public static func magnitude(at point: SIMD3<Double>, dueTo charges: [PointCharge]) -> Double {
        simd_length(vector(at: point, dueTo: charges))
    }

    /// Potential (V) from one point charge: V = k·q/r, zero reference at infinity.
    public static func potential(at point: SIMD3<Double>, dueTo charge: PointCharge) -> Double {
        let distance = simd_distance(point, charge.position)
        guard distance > singularityRadius else { return 0 }
        return k * charge.charge / distance
    }

    /// Potential at `point` due to any number of charges (scalar superposition).
    public static func potential(at point: SIMD3<Double>, dueTo charges: [PointCharge]) -> Double {
        charges.reduce(0) { total, charge in
            total + potential(at: point, dueTo: charge)
        }
    }
}
