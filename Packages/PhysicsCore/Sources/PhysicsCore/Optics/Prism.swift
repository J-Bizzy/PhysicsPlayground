//
//  Prism.swift
//  PhysicsCore — Optics: 2D trace through a triangular prism, real Snell + TIR; minimum deviation and dispersion emerge rather than being drawn.
//

import Foundation
import simd

public enum Prism {
    /// An isosceles prism: apex angle at the top, standing on its base.
    public struct Geometry: Sendable, Equatable {
        public var apex: SIMD2<Double>
        public var apexAngle: Double
        /// Rotation about the apex, rad; positive = counterclockwise.
        public var rotation: Double
        /// Slant side length, apex to base corner.
        public var sideLength: Double

        public init(apex: SIMD2<Double>, apexAngle: Double,
                    rotation: Double = 0, sideLength: Double = 0.24) {
            self.apex = apex
            self.apexAngle = apexAngle
            self.rotation = rotation
            self.sideLength = sideLength
        }

        /// Corners: apex, base-left, base-right (after rotation).
        public var vertices: [SIMD2<Double>] {
            let half = apexAngle / 2
            let left = SIMD2(-sin(half), -cos(half)) * sideLength
            let right = SIMD2(sin(half), -cos(half)) * sideLength
            return [apex, apex + rotated(left), apex + rotated(right)]
        }

        func rotated(_ v: SIMD2<Double>) -> SIMD2<Double> {
            SIMD2(v.x * cos(rotation) - v.y * sin(rotation),
                  v.x * sin(rotation) + v.y * cos(rotation))
        }
    }

    struct Face {
        var a: SIMD2<Double>
        var b: SIMD2<Double>
        /// Unit outward normal.
        var normal: SIMD2<Double>
    }

    static func faces(of geometry: Geometry) -> [Face] {
        let v = geometry.vertices
        // Outward normals pushed away from the centroid — immune to winding mistakes.
        let centroid = (v[0] + v[1] + v[2]) / 3
        func face(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Face {
            let edge = simd_normalize(b - a)
            var normal = SIMD2(-edge.y, edge.x)
            if simd_dot(normal, (a + b) / 2 - centroid) < 0 { normal = -normal }
            return Face(a: a, b: b, normal: normal)
        }
        return [face(v[0], v[1]),   // left slant
                face(v[0], v[2]),   // right slant
                face(v[1], v[2])]   // base
    }

    /// Polyline: origin, entry, internal reflections, exit, then `escape` past the last surface. Misses go straight.
    public static func trace(
        from origin: SIMD2<Double>, direction: SIMD2<Double>,
        geometry: Geometry, index n: Double,
        escape: Double = 0.6, maxInternalBounces: Int = 4
    ) -> [SIMD2<Double>] {
        let prismFaces = faces(of: geometry)
        var d = simd_normalize(direction)
        var p = origin
        var points = [p]

        guard let entry = nearestHit(from: p, direction: d, faces: prismFaces,
                                     excluding: -1) else {
            return [p, p + d * escape]
        }
        p = entry.point
        points.append(p)
        // Entering: refract wants the normal against the ray — the outward one already is.
        guard let inside = Refraction.refract(
            direction: SIMD3(d.x, d.y, 0), normal: SIMD3(entry.face.normal.x, entry.face.normal.y, 0),
            n1: 1.0, n2: n
        ) else {
            let r = Refraction.reflect(
                direction: SIMD3(d.x, d.y, 0),
                normal: SIMD3(entry.face.normal.x, entry.face.normal.y, 0))
            points.append(p + SIMD2(r.x, r.y) * escape)
            return points
        }
        d = SIMD2(inside.x, inside.y)

        var currentFace = entry.index
        for _ in 0..<maxInternalBounces {
            guard let hit = nearestHit(from: p, direction: d, faces: prismFaces,
                                       excluding: currentFace) else { break }
            p = hit.point
            points.append(p)
            currentFace = hit.index
            // Leaving: the refract normal must oppose the ray, i.e. point into the glass.
            if let out = Refraction.refract(
                direction: SIMD3(d.x, d.y, 0),
                normal: SIMD3(-hit.face.normal.x, -hit.face.normal.y, 0),
                n1: n, n2: 1.0
            ) {
                d = SIMD2(out.x, out.y)
                points.append(p + d * escape)
                return points
            }
            let r = Refraction.reflect(
                direction: SIMD3(d.x, d.y, 0),
                normal: SIMD3(hit.face.normal.x, hit.face.normal.y, 0))
            d = SIMD2(r.x, r.y)
        }
        points.append(p + d * escape)
        return points
    }

    private static func nearestHit(
        from origin: SIMD2<Double>, direction: SIMD2<Double>,
        faces: [Face], excluding: Int
    ) -> (point: SIMD2<Double>, face: Face, index: Int)? {
        var best: (Double, SIMD2<Double>, Face, Int)?
        for (index, face) in faces.enumerated() where index != excluding {
            let denominator = simd_dot(direction, face.normal)
            guard abs(denominator) > 1e-12 else { continue }
            let t = simd_dot(face.a - origin, face.normal) / denominator
            guard t > 1e-9 else { continue }
            let point = origin + t * direction
            let edge = face.b - face.a
            let along = simd_dot(point - face.a, edge) / simd_length_squared(edge)
            guard along >= -1e-9, along <= 1 + 1e-9 else { continue }
            if best == nil || t < best!.0 {
                best = (t, point, face, index)
            }
        }
        guard let best else { return nil }
        return (best.1, best.2, best.3)
    }

    /// Minimum deviation for symmetric passage: δmin = 2·asin(n·sin(A/2)) − A.
    public static func minimumDeviation(apexAngle: Double, index n: Double) -> Double {
        2 * asin(n * sin(apexAngle / 2)) - apexAngle
    }
}
