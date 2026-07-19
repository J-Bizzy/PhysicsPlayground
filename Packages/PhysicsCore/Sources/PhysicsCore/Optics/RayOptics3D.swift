//
//  RayOptics3D.swift
//  PhysicsCore — Optics
//
//  Full three-dimensional tracing through ideal thin elements on a
//  common optical axis (+x). This is not a small-angle approximation
//  of the 2D bench: an ideal thin lens is DEFINED by the reduced-slope
//  transform s' = s − h/f applied to the ray's lateral offset h — in
//  3D, h and s are 2D lateral vectors, and the same one-line law
//  focuses a whole cone of rays. Parallel bundles meet the focal
//  point exactly; a point source images exactly where 1/f = 1/dₒ+1/dᵢ
//  says — the image EMERGES from the trace, per house rule.
//
//  Mirrors are flat and fold the axial direction; screens absorb.
//  Rays outside an element's aperture pass it untouched.
//

import Foundation
import simd

public enum RayOptics3D {
    public struct Element: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// Positive focal length converges; negative diverges.
            case lens(focalLength: Double)
            case mirror
            case screen
        }
        public var x: Double
        public var kind: Kind
        /// Lateral aperture radius: rays farther off-axis pass by.
        public var apertureRadius: Double

        public init(x: Double, kind: Kind, apertureRadius: Double = 0.17) {
            self.x = x
            self.kind = kind
            self.apertureRadius = apertureRadius
        }
    }

    public struct Ray: Sendable {
        public var origin: SIMD3<Double>
        public var direction: SIMD3<Double>
        public init(origin: SIMD3<Double>, direction: SIMD3<Double>) {
            self.origin = origin
            self.direction = simd_normalize(direction)
        }
    }

    /// A circular parallel beam marching +x: a center ray plus rings.
    public static func parallelBeam(
        fromX x: Double, center: SIMD3<Double>, radius: Double,
        rings: Int = 3, spokes: Int = 8
    ) -> [Ray] {
        var rays = [Ray(origin: SIMD3(x, center.y, center.z), direction: SIMD3(1, 0, 0))]
        for ring in 1...max(rings, 1) {
            let r = radius * Double(ring) / Double(max(rings, 1))
            for spoke in 0..<spokes {
                let phi = 2 * .pi * Double(spoke) / Double(spokes)
                rays.append(Ray(
                    origin: SIMD3(x, center.y + r * sin(phi), center.z + r * cos(phi)),
                    direction: SIMD3(1, 0, 0)))
            }
        }
        return rays
    }

    /// A cone of rays from a point source aimed down +x.
    public static func pointCone(
        from origin: SIMD3<Double>, halfAngle: Double,
        rings: Int = 3, spokes: Int = 8
    ) -> [Ray] {
        var rays = [Ray(origin: origin, direction: SIMD3(1, 0, 0))]
        for ring in 1...max(rings, 1) {
            let angle = halfAngle * Double(ring) / Double(max(rings, 1))
            for spoke in 0..<spokes {
                let phi = 2 * .pi * Double(spoke) / Double(spokes)
                rays.append(Ray(
                    origin: origin,
                    direction: SIMD3(cos(angle),
                                     sin(angle) * sin(phi),
                                     sin(angle) * cos(phi))))
            }
        }
        return rays
    }

    /// Traces each ray through the elements (any axial travel
    /// direction), returning one polyline per ray. `axisCenter` is the
    /// optical axis's y/z; `bounds` clips the march in x.
    public static func trace(
        rays: [Ray], elements: [Element],
        axisCenter: SIMD3<Double>, bounds: ClosedRange<Double>
    ) -> [[SIMD3<Double>]] {
        rays.map { trace(ray: $0, elements: elements, axisCenter: axisCenter, bounds: bounds) }
    }

    public static func trace(
        ray: Ray, elements: [Element],
        axisCenter: SIMD3<Double>, bounds: ClosedRange<Double>
    ) -> [SIMD3<Double>] {
        var points = [ray.origin]
        var origin = ray.origin
        var direction = ray.direction
        var passed = Set<Int>()

        for _ in 0..<(elements.count * 2 + 1) {
            let axial = direction.x
            guard abs(axial) > 1e-9 else { break }

            // Nearest un-passed element plane ahead in the travel direction.
            var nextIndex: Int?
            var nextT = Double.infinity
            for (index, element) in elements.enumerated() where !passed.contains(index) {
                let t = (element.x - origin.x) / axial
                guard t > 1e-9, t < nextT else { continue }
                nextT = t
                nextIndex = index
            }
            guard let index = nextIndex else { break }
            let element = elements[index]
            let hit = origin + nextT * direction
            passed.insert(index)
            // A mirror folds travel: planes behind become reachable again.
            // (Cheap correctness: allow re-crossing everything but this one.)

            let lateral = SIMD2(hit.y - axisCenter.y, hit.z - axisCenter.z)
            if simd_length(lateral) > element.apertureRadius {
                continue  // misses the glass; the plane doesn't exist for it
            }
            points.append(hit)
            origin = hit

            switch element.kind {
            case .lens(let focalLength):
                // Reduced coordinates in the travel frame: s' = s − h/f.
                let sign = axial > 0 ? 1.0 : -1.0
                let slope = SIMD2(direction.y, direction.z) / abs(axial)
                let bent = slope - lateral / focalLength
                direction = simd_normalize(SIMD3(sign, bent.x * sign, bent.y * sign))
                if axial > 0 { passed = passed.union([]) }
            case .mirror:
                direction = SIMD3(-direction.x, direction.y, direction.z)
                passed = [index]  // fold: everything is crossable again
            case .screen:
                return points  // absorbed
            }
        }

        // March to the bounds edge.
        let axial = direction.x
        if abs(axial) > 1e-9 {
            let edge = axial > 0 ? bounds.upperBound : bounds.lowerBound
            let t = (edge - origin.x) / axial
            if t > 1e-9 {
                points.append(origin + t * direction)
            }
        }
        return points
    }

    /// Where a traced polyline crosses the plane x = at (nil if never).
    public static func lateralPoint(
        of line: [SIMD3<Double>], atX x: Double
    ) -> SIMD3<Double>? {
        for (a, b) in zip(line, line.dropFirst()) {
            let da = x - a.x
            let db = x - b.x
            guard da * db <= 0, abs(b.x - a.x) > 1e-12 else { continue }
            let t = da / (b.x - a.x)
            return a + t * (b - a)
        }
        return nil
    }
}
