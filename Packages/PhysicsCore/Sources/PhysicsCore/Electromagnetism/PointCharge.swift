//
//  PointCharge.swift
//  Pure model type for the physics layer (no RealityKit/SwiftUI). SI: position in meters, charge in Coulombs.
//

import Foundation
import simd

public struct PointCharge: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var position: SIMD3<Double>
    public var charge: Double

    public init(id: UUID = UUID(), position: SIMD3<Double>, charge: Double) {
        self.id = id
        self.position = position
        self.charge = charge
    }

    public var isPositive: Bool { charge >= 0 }

    /// Magnitude in microcoulombs, for UI display.
    public var magnitudeMicroCoulombs: Double { abs(charge) * 1e6 }
}
