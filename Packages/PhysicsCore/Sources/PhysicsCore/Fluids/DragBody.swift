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
    /// Modern sedan (automotive Cd, referenced to frontal area).
    case car
    /// Box truck — the bluff body every highway knows.
    case truck
    /// Light aircraft: streamlined fuselage, wings edge-on.
    case plane

    public var id: String { rawValue }

    /// The three real-world vehicles (vs. the canonical lab shapes).
    public var isVehicle: Bool {
        switch self {
        case .car, .truck, .plane: true
        default: false
        }
    }

    /// Vehicles present 2.2× larger than the lab shapes at the same
    /// size setting, so the flow visibly works around them. This is the
    /// single knob the renderer scale, the frontal area, and the
    /// streamline deflection radius all share — size and physics agree.
    public var sizeMultiplier: Double { isVehicle ? 2.2 : 1 }

    /// Measured drag coefficient at high (subcritical) Reynolds number.
    public var dragCoefficient: Double {
        switch self {
        case .cylinder: 1.17
        case .sphere: 0.47
        case .teardrop: 0.04
        case .cube: 1.05
        case .flatDisc: 1.17
        case .cone: 0.50
        case .car: 0.30
        case .truck: 0.80
        case .plane: 0.09
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
        case .car:
            // Sedan silhouette (1.85 m wide × 1.45 m tall): 2r × 1.57r.
            (2 * radius) * (1.57 * radius)
        case .truck:
            // Semi tractor-trailer (2.55 m wide × 3.95 m tall): 2r × 3.1r.
            (2 * radius) * (3.1 * radius)
        case .plane:
            // Slender airliner: the fuselage radius is 0.4 of the
            // half-width scale (A320 class: 1.98 m radius, 35.8 m span);
            // the wings meet the flow edge-on.
            .pi * (0.4 * radius) * (0.4 * radius)
        }
    }

    /// A visualization-grade sphere silhouette of the body for flow
    /// deflection: streamlines and particles slip around these spheres
    /// (ObstacleField), so the flow wraps the actual shape — tight over
    /// a sedan's cabin, wide around a box truck, barely rippled by a
    /// slender fuselage. Local coords: x downstream, y up, z lateral;
    /// offsets and radii scale with the frontal half-width, matching
    /// each body's authored proportions. The cylinder returns none —
    /// it keeps its exact analytic solution.
    public func obstacleSpheres(center: SIMD3<Double>, halfWidth: Double) -> [ObstacleField.Sphere] {
        let layout: [(x: Double, y: Double, r: Double)]
        switch self {
        case .cylinder:
            return []
        case .sphere:
            layout = [(0, 0, 1.0)]
        case .teardrop:
            layout = [(-0.5, 0, 0.95), (0.5, 0, 0.6), (1.3, 0, 0.32)]
        case .cube:
            layout = [(0, 0, 1.25)]
        case .flatDisc:
            layout = [(0, 0, 1.35)]
        case .cone:
            layout = [(-0.8, 0, 0.45), (0.15, 0, 1.0)]
        case .car:
            // Sedan silhouette: low nose, high cabin, tapering tail.
            layout = [(-2.0, -0.25, 0.62), (-1.0, -0.15, 0.78), (0.1, 0.1, 0.95),
                      (1.2, -0.05, 0.75), (2.05, -0.2, 0.55)]
        case .truck:
            // Long tall box: near-constant girth nose to tail.
            layout = [(-3.9, 0, 1.45), (-2.0, 0, 1.53), (0, 0, 1.53),
                      (2.0, 0, 1.53), (3.9, 0, 1.45)]
        case .plane:
            // Slender fuselage: the wind barely notices.
            layout = [(-3.4, 0, 0.35), (-1.7, 0, 0.45), (0, 0, 0.45),
                      (1.7, 0, 0.42), (3.2, 0, 0.3)]
        }
        return layout.map {
            ObstacleField.Sphere(
                center: center + SIMD3($0.x * halfWidth, $0.y * halfWidth, 0),
                radius: $0.r * halfWidth)
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
