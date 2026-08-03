//
//  CurrentLoop.swift
//  PhysicsCore — Magnetism
//
//  The bridge between the circuit bench and the field bench.
//
//  A coil carrying a current IS a magnet: N turns of area A carrying
//  current I have magnetic moment m = N·I·A, pointing along the coil
//  axis by the right-hand rule. That single identity is what connects
//  the two halves of electromagnetism, and it is the reason the two
//  modules should be able to talk to each other: build a circuit, read
//  the current it actually delivers, and put THAT number into the field
//  as a magnet you can carry around.
//
//  Everything here is exact. The far field of a real loop is the ideal
//  dipole field the rest of the Magnetism code already computes, and
//  the on-axis expression below is the exact Biot–Savart result for a
//  circular loop — so the two can be checked against each other, which
//  is what the tests do.
//

import Foundation
import simd

public enum CurrentLoop {
    /// Vacuum permeability, T·m/A.
    public static let mu0 = Constants.vacuumPermeability

    /// Magnetic moment magnitude of a coil: m = N·I·A, in A·m².
    public static func momentMagnitude(turns: Int, current: Double, area: Double) -> Double {
        Double(turns) * current * area
    }

    /// The area of a circular coil of the given radius.
    public static func area(radius: Double) -> Double {
        .pi * radius * radius
    }

    /// A coil, as the ideal dipole the field code understands.
    ///
    /// The moment points along `axis` by the right-hand rule; a negative
    /// current reverses it, which is exactly what reversing the battery
    /// does to a real electromagnet.
    public static func magnet(
        at position: SIMD3<Double>,
        axis: SIMD3<Double>,
        turns: Int,
        current: Double,
        radius: Double
    ) -> BarMagnet {
        let unit = simd_length(axis) > 1e-12 ? simd_normalize(axis) : SIMD3(1, 0, 0)
        let m = momentMagnitude(turns: turns, current: current, area: area(radius: radius))
        return BarMagnet(position: position, moment: unit * m)
    }

    /// EXACT on-axis field of a circular loop, T:
    ///     B(z) = μ₀ N I a² / (2 (a² + z²)^{3/2})
    /// measured from the loop's centre along its axis.
    public static func axialField(turns: Int, current: Double,
                                  radius: Double, distance z: Double) -> Double {
        let a2 = radius * radius
        let denominator = 2 * pow(a2 + z * z, 1.5)
        guard denominator > 0 else { return 0 }
        return mu0 * Double(turns) * current * a2 / denominator
    }

    /// Field at the very centre of the loop: μ₀NI/2a — the special case
    /// everyone memorises, and a useful sanity anchor.
    public static func centreField(turns: Int, current: Double, radius: Double) -> Double {
        guard radius > 0 else { return 0 }
        return mu0 * Double(turns) * current / (2 * radius)
    }
}
