//  CurrentLoop.swift — circuit↔field bridge: a coil IS a magnet, m = N·I·A along the axis
//  (right-hand rule). Exact throughout; the on-axis Biot–Savart result cross-checks the
//  dipole far field in tests.

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

    /// A coil as the ideal dipole the field code understands; a negative current reverses
    /// the moment, exactly as reversing the battery does to a real electromagnet.
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

    /// EXACT on-axis field of a circular loop, T: B(z) = μ₀NIa²/(2(a²+z²)^{3/2}), z from centre.
    public static func axialField(turns: Int, current: Double,
                                  radius: Double, distance z: Double) -> Double {
        let a2 = radius * radius
        let denominator = 2 * pow(a2 + z * z, 1.5)
        guard denominator > 0 else { return 0 }
        return mu0 * Double(turns) * current * a2 / denominator
    }

    /// Centre-of-loop field: μ₀NI/2a — the memorised special case, a sanity anchor.
    public static func centreField(turns: Int, current: Double, radius: Double) -> Double {
        guard radius > 0 else { return 0 }
        return mu0 * Double(turns) * current / (2 * radius)
    }
}
