//
//  BarMagnet.swift
//  PhysicsCore — Magnetism
//
//  A bar magnet, modelled as an ideal magnetic dipole: a point with a
//  magnetic moment vector m (A·m²). The moment points from the south
//  pole toward the north pole, and its magnitude is the magnet's
//  strength. Pure Swift + simd, SI units, no rendering.
//

import Foundation
import simd

public struct BarMagnet: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Centre of the magnet, metres.
    public var position: SIMD3<Double>
    /// Magnetic dipole moment (A·m²): direction = S→N, magnitude = strength.
    public var moment: SIMD3<Double>

    public init(id: UUID = UUID(), position: SIMD3<Double>, moment: SIMD3<Double>) {
        self.id = id
        self.position = position
        self.moment = moment
    }

    /// Strength |m| in A·m².
    public var strength: Double { simd_length(moment) }

    /// Unit direction from the south pole toward the north pole.
    public var axis: SIMD3<Double> {
        let s = strength
        return s > 1e-12 ? moment / s : SIMD3(0, 1, 0)
    }

    /// The world position of a pole, for a bar of the given length.
    public func pole(north: Bool, length: Double) -> SIMD3<Double> {
        position + (north ? 0.5 : -0.5) * length * axis
    }
}
