//
//  DragBody.swift
//  Canonical drag bodies + F = ½ρv²·Cd·A; Cd values are measured high-Re wind-tunnel data (White; Hoerner), not derivable from ideal-flow theory.
//

import Foundation
import simd

public enum DragBody: String, CaseIterable, Sendable, Identifiable {
    /// Long circular cylinder in crossflow (has the exact ideal-flow solution).
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

    /// Human-readable name, for readouts and the notebook.
    public var displayName: String {
        switch self {
        case .cylinder: "Cylinder"
        case .sphere: "Sphere"
        case .teardrop: "Teardrop"
        case .cube: "Cube"
        case .flatDisc: "Flat disc"
        case .cone: "Cone"
        case .car: "Car"
        case .truck: "Box truck"
        case .plane: "Airliner"
        }
    }

    /// The three real-world vehicles (vs. the canonical lab shapes).
    public var isVehicle: Bool {
        switch self {
        case .car, .truck, .plane: true
        default: false
        }
    }

    /// Vehicles present 2.2× larger — the single knob renderer scale, frontal area, and deflection radius all share, so size and physics agree.
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

    /// Frontal (projected) area, m², for a body of frontal half-width `radius`; the cylinder's
    /// reference area is diameter × span.
    public func frontalArea(radius: Double, cylinderSpan: Double = 1.0) -> Double {
        switch self {
        case .cylinder:
            2 * radius * cylinderSpan
        case .cube:
            // Face = (2r)², from the physics half-width only — never a rendering-layer mesh ratio.
            (2 * radius) * (2 * radius)
        case .sphere, .teardrop, .flatDisc, .cone:
            .pi * radius * radius
        case .car:
            // Sedan silhouette (1.85 m wide × 1.45 m tall): 2r × 1.57r.
            (2 * radius) * (1.57 * radius)
        case .truck:
            // Semi tractor-trailer (2.55 m wide × 3.95 m tall): 2r × 3.1r.
            (2 * radius) * (3.1 * radius)
        case .plane:
            // Slender airliner: fuselage radius 0.4× the half-width (A320 class); wings edge-on.
            .pi * (0.4 * radius) * (0.4 * radius)
        }
    }

    /// Visualization-grade sphere silhouette for flow deflection (ObstacleField); local coords x
    /// downstream, y up, z lateral, scaled by frontal half-width. Spheres must sit tightly inside the visible model — radii proud of the silhouette read as invisible bulges. Cylinder returns none (keeps its analytic solution).
    public func obstacleSpheres(center: SIMD3<Double>, halfWidth: Double) -> [ObstacleField.Sphere] {
        let layout: [(x: Double, y: Double, r: Double)]
        switch self {
        case .cylinder:
            return []
        case .sphere:
            layout = [(0, 0, 1.0)]
        case .teardrop:
            layout = [(-0.8, 0, 0.62), (-0.35, 0, 0.8), (0.15, 0, 0.78),
                      (0.7, 0, 0.6), (1.2, 0, 0.4), (1.6, 0, 0.22)]
        case .cube:
            // Inscribed, not circumscribed: core + corner spheres inside the half-edge (0.883).
            layout = [(0, 0, 0.80),
                      (-0.52, -0.52, 0.34), (-0.52, 0.52, 0.34),
                      (0.52, -0.52, 0.34), (0.52, 0.52, 0.34)]
        case .flatDisc:
            layout = [(0, 0, 0.5),
                      (0, 0.72, 0.28), (0, -0.72, 0.28)]
        case .cone:
            layout = [(-0.85, 0, 0.22), (-0.45, 0, 0.45),
                      (0.0, 0, 0.7), (0.4, 0, 0.9)]
        case .car:
            layout = [(-2.1, -0.4, 0.34), (-1.5, -0.3, 0.46),
                      (-0.8, -0.2, 0.56), (-0.1, 0.0, 0.64),
                      (0.6, 0.0, 0.6), (1.3, -0.15, 0.5),
                      (1.9, -0.3, 0.4), (2.3, -0.4, 0.3)]
        case .truck:
            layout = [(-3.8, 0, 1.2), (-2.6, 0, 1.32), (-1.3, 0, 1.35),
                      (0, 0, 1.35), (1.3, 0, 1.35), (2.6, 0, 1.32),
                      (3.8, 0, 1.2)]
        case .plane:
            layout = [(-3.3, 0, 0.28), (-2.2, 0, 0.36), (-1.1, 0, 0.4),
                      (0, 0, 0.4), (1.1, 0, 0.38), (2.2, 0, 0.32),
                      (3.1, 0, 0.24)]
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

/// Sphere obstacles that deflect a velocity field (hands, room surfaces). Visualization-grade —
/// radial exclusion + tangential slip, not Navier–Stokes — and the UI discloses that.
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

    /// Bends `velocity` around every nearby obstacle: inside a sphere the into-surface component
    /// is removed plus an outward push; within one radius it fades smoothly; far away, untouched.
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
                // Approach shell: fade the into-surface component to zero at the surface (slip).
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
