//
//  ElectricField.swift
//  PhysicsPlayground
//
//  Coulomb's Law and superposition, as pure functions. This file is the
//  physics core of the app: the renderer only ever *asks* this layer for
//  field vectors — it never computes physics itself.
//

import Foundation
import simd

nonisolated enum ElectricField {
    /// Coulomb constant k = 1/(4πε₀) in N·m²/C².
    static let k = 8.9875517923e9

    /// Separations below this (meters) are treated as "at the charge itself,"
    /// where the 1/r² field is singular. We return a zero vector there and let
    /// the rendering layer decide how to present it (it hides those arrows).
    static let singularityRadius = 1e-6

    /// Electric field at `point` due to a single point charge.
    ///
    /// Coulomb's Law: **E** = k·q/r² · r̂, where r̂ points from the charge
    /// toward the field point. Computed as k·q·**r** / |r|³ to avoid a
    /// separate normalization step.
    static func vector(at point: SIMD3<Double>, dueTo charge: PointCharge) -> SIMD3<Double> {
        let r = point - charge.position
        let distanceSquared = simd_length_squared(r)
        guard distanceSquared > singularityRadius * singularityRadius else {
            return .zero
        }
        let distance = distanceSquared.squareRoot()
        return (k * charge.charge / (distanceSquared * distance)) * r
    }

    /// Electric field at `point` due to any number of charges, by vector
    /// superposition: the total field is the sum of each charge's field.
    static func vector(at point: SIMD3<Double>, dueTo charges: [PointCharge]) -> SIMD3<Double> {
        charges.reduce(.zero) { total, charge in
            total + vector(at: point, dueTo: charge)
        }
    }

    /// Field magnitude in N/C at `point` — a convenience for display code.
    static func magnitude(at point: SIMD3<Double>, dueTo charges: [PointCharge]) -> Double {
        simd_length(vector(at: point, dueTo: charges))
    }

    /// Electric potential (volts) at `point` due to a single point charge:
    /// V = k·q/r, with the zero reference at infinity. Unlike the field this
    /// is a scalar, so superposition is a plain sum — no vectors involved.
    static func potential(at point: SIMD3<Double>, dueTo charge: PointCharge) -> Double {
        let distance = simd_distance(point, charge.position)
        guard distance > singularityRadius else { return 0 }
        return k * charge.charge / distance
    }

    /// Potential at `point` due to any number of charges (scalar superposition).
    static func potential(at point: SIMD3<Double>, dueTo charges: [PointCharge]) -> Double {
        charges.reduce(0) { total, charge in
            total + potential(at: point, dueTo: charge)
        }
    }
}
