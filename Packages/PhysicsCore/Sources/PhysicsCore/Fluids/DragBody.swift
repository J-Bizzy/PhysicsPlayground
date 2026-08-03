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
            // The cube's reference area is its face, edge².
            //
            // This read `(2·radius·0.883)²` until 2026-08-03, where
            // 0.883 was `0.053/0.06` — A RATIO OF TWO MESH DIMENSIONS
            // FROM THE RENDERING LAYER, the one place in this package
            // where a visual constant reached into a physical quantity.
            // It made the reported drag on a cube about 22 % low against
            // its own stated reference. The comment that carried it was
            // a piece of thinking-aloud ("…? No: …") rather than a
            // statement, which is its own tell.
            //
            // `radius` here is the frontal HALF-WIDTH every body in this
            // enum is described by, so a cube of that half-width has
            // edge 2r and face (2r)². If the renderer wants a cube that
            // looks the same width as a sphere, that is the renderer's
            // scale to choose; the physics gets the cube it is told it
            // has.
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
    ///
    /// These must sit INSIDE the visible model, tightly: the smoke
    /// wraps whatever is here, so an oversized sphere reads as an
    /// invisible bulge jutting out of the bodywork — which is exactly
    /// how the first coarse layouts (few spheres, radii proud of the
    /// silhouette) looked. More, smaller spheres trace each shape so
    /// the air curves hug the model.
    public func obstacleSpheres(center: SIMD3<Double>, halfWidth: Double) -> [ObstacleField.Sphere] {
        let layout: [(x: Double, y: Double, r: Double)]
        switch self {
        case .cylinder:
            return []
        case .sphere:
            layout = [(0, 0, 1.0)]
        case .teardrop:
            // The profile itself: fattest just behind the nose, a
            // smooth chain thinning to the tail.
            layout = [(-0.8, 0, 0.62), (-0.35, 0, 0.8), (0.15, 0, 0.78),
                      (0.7, 0, 0.6), (1.2, 0, 0.4), (1.6, 0, 0.22)]
        case .cube:
            // Inscribed, not circumscribed — a sphere poking through
            // six flat faces is the bulge complaint incarnate. A core
            // plus four corner spheres fill the profile from inside,
            // all of them within the inscribed half-edge (0.883).
            layout = [(0, 0, 0.80),
                      (-0.52, -0.52, 0.34), (-0.52, 0.52, 0.34),
                      (0.52, -0.52, 0.34), (0.52, 0.52, 0.34)]
        case .flatDisc:
            // Thin and face-on: a hub plus two rim spheres reaching
            // exactly to the rim, not one deep ball.
            layout = [(0, 0, 0.5),
                      (0, 0.72, 0.28), (0, -0.72, 0.28)]
        case .cone:
            // Apex into the wind, widening to the base.
            layout = [(-0.85, 0, 0.22), (-0.45, 0, 0.45),
                      (0.0, 0, 0.7), (0.4, 0, 0.9)]
        case .car:
            // Sedan silhouette, hugged: low nose, glasshouse crown,
            // tapering tail — nothing above the roofline.
            layout = [(-2.1, -0.4, 0.34), (-1.5, -0.3, 0.46),
                      (-0.8, -0.2, 0.56), (-0.1, 0.0, 0.64),
                      (0.6, 0.0, 0.6), (1.3, -0.15, 0.5),
                      (1.9, -0.3, 0.4), (2.3, -0.4, 0.3)]
        case .truck:
            // Long tall box: constant girth, radii inside the panels.
            layout = [(-3.8, 0, 1.2), (-2.6, 0, 1.32), (-1.3, 0, 1.35),
                      (0, 0, 1.35), (1.3, 0, 1.35), (2.6, 0, 1.32),
                      (3.8, 0, 1.2)]
        case .plane:
            // Slender fuselage: the wind barely notices.
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
