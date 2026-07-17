//
//  DragBody.swift
//  PhysicsCore — Fluids
//
//  Canonical drag-test bodies with measured drag coefficients, and the
//  drag equation F = ½ρv²·Cd·A. The coefficients are the standard
//  high-Reynolds-number wind-tunnel values found in fluid-dynamics
//  references (White, "Fluid Mechanics"; Hoerner, "Fluid-Dynamic
//  Drag") — this is empirical data, not something we can derive from
//  ideal-flow theory (which famously predicts zero drag).
//

import Foundation
import simd

public enum DragBody: String, CaseIterable, Sendable, Identifiable {
    /// Long circular cylinder in crossflow (the exact-ideal-flow star
    /// of the tunnel).
    case cylinder
    /// Smooth sphere, subcritical Re.
    case sphere
    /// Streamlined teardrop body, the shape drag forgot.
    case teardrop
    /// Cube, flat face to the flow.
    case cube
    /// Thin flat disc, face-on.
    case flatDisc
    /// Cone, apex into the flow (~30° half-angle class).
    case cone

    public var id: String { rawValue }

    /// Measured drag coefficient at high (subcritical) Reynolds number.
    public var dragCoefficient: Double {
        switch self {
        case .cylinder: 1.17
        case .sphere: 0.47
        case .teardrop: 0.04
        case .cube: 1.05
        case .flatDisc: 1.17
        case .cone: 0.50
        }
    }

    /// Frontal (projected) area for a body whose frontal half-width is
    /// `radius`, in m². The cylinder's reference area is diameter ×
    /// span; every other body presents a circular or square face.
    public func frontalArea(radius: Double, cylinderSpan: Double = 1.0) -> Double {
        switch self {
        case .cylinder:
            2 * radius * cylinderSpan
        case .cube:
            // Frontal half-width r → edge 2r·(1/√2)? No: the cube is
            // sized so its face matches the circular bodies' width —
            // edge = 2·radius·(0.053/0.06) in the app, but physically
            // the reference is simply edge²; use the inscribed edge.
            (2 * radius * 0.883) * (2 * radius * 0.883)
        case .sphere, .teardrop, .flatDisc, .cone:
            .pi * radius * radius
        }
    }

    /// The drag equation: F = ½ · ρ · v² · Cd · A  (newtons).
    public static func dragForce(
        airDensity: Double, speed: Double, dragCoefficient: Double, frontalArea: Double
    ) -> Double {
        0.5 * airDensity * speed * speed * dragCoefficient * frontalArea
    }
}

/// Sphere obstacles that deflect a velocity field — the mechanism behind
/// airflow bending around tracked hands and reconstructed room surfaces.
/// This is a visualization-grade model (radial exclusion + tangential
/// slip), not a Navier–Stokes solve, and the UI discloses that.
public struct ObstacleField: Sendable, Equatable {
    public struct Sphere: Sendable, Equatable {
        public var center: SIMD3<Double>
        public var radius: Double
        public init(center: SIMD3<Double>, radius: Double) {
            self.center = center
            self.radius = radius
        }
    }

    public var spheres: [Sphere]

    public init(spheres: [Sphere] = []) {
        self.spheres = spheres
    }

    /// Bends `velocity` at `point` around every nearby obstacle: inside
    /// a sphere the normal (into-surface) component is removed and a
    /// gentle outward push added; within one radius of the surface the
    /// normal component fades smoothly. Far from all obstacles the
    /// velocity is untouched.
    public func deflected(_ velocity: SIMD3<Double>, at point: SIMD3<Double>) -> SIMD3<Double> {
        var v = velocity
        for sphere in spheres {
            let offset = point - sphere.center
            let distance = simd_length(offset)
            let influence = 2 * sphere.radius
            guard distance < influence, distance > 1e-9 else { continue }
            let normal = offset / distance

            if distance < sphere.radius {
                // Inside: strip inward flow entirely and push out.
                let inward = min(simd_dot(v, normal), 0)
                v -= inward * normal
                v += normal * (sphere.radius - distance) * 8
            } else {
                // Approach shell: fade the into-surface component to
                // zero at the surface (slip condition).
                let inward = simd_dot(v, normal)
                if inward < 0 {
                    let fade = (distance - sphere.radius) / sphere.radius  // 0 at surface, 1 at 2r
                    v -= inward * normal * (1 - fade)
                }
            }
        }
        return v
    }
}
