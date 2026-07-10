//
//  PointCharge.swift
//  PhysicsPlayground
//
//  Pure model type for the physics layer. No RealityKit or SwiftUI imports —
//  everything in Physics/ is plain Swift + simd so it can be unit tested
//  without a simulator or any rendering machinery.
//
//  Units are SI throughout the physics layer:
//    position — meters
//    charge   — Coulombs
//

import Foundation
import simd

nonisolated struct PointCharge: Identifiable, Equatable {
    let id: UUID
    var position: SIMD3<Double>
    var charge: Double

    init(id: UUID = UUID(), position: SIMD3<Double>, charge: Double) {
        self.id = id
        self.position = position
        self.charge = charge
    }

    var isPositive: Bool { charge >= 0 }

    /// Magnitude in microcoulombs — convenient for UI display, since
    /// tabletop-scale demos use µC-order charges.
    var magnitudeMicroCoulombs: Double { abs(charge) * 1e6 }
}
