//
//  PointCharge.swift
//  PhysicsCore — Electromagnetism
//
//  Pure model type for the physics layer. No RealityKit or SwiftUI imports —
//  everything in PhysicsCore is plain Swift + simd so it can be unit tested
//  without a simulator or any rendering machinery.
//
//  Units are SI throughout the physics layer:
//    position — meters
//    charge   — Coulombs
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

    /// Magnitude in microcoulombs — convenient for UI display, since
    /// tabletop-scale demos use µC-order charges.
    public var magnitudeMicroCoulombs: Double { abs(charge) * 1e6 }
}
