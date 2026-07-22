//
//  GlassBlock.swift
//  PhysicsCore — Optics
//
//  A rectangular glass slab traced with real 3D refraction: the ray
//  bends at the entry face (Snell), crosses the glass, and either
//  refracts out or — past the critical angle — mirrors off the inside
//  of a face and tries the next one, bouncing along like light in a
//  fiber. The textbook results emerge: a slab passes the ray PARALLEL
//  to how it arrived (only laterally shifted), and steep entries turn
//  the slab into a light pipe. Both pinned by the tests.
//

import Foundation
import simd

public enum GlassBlock {
    /// One face hit on an axis-aligned box: entry point and the
    /// OUTWARD unit normal of the struck face.
    public struct FaceHit: Sendable {
        public var point: SIMD3<Double>
        public var normal: SIMD3<Double>
    }

    /// First intersection of a ray with the box surface from OUTSIDE,
    /// or nil if it misses. Standard slab method; the normal comes
    /// from whichever axis produced the entry time.
    public static func entry(
        from origin: SIMD3<Double>, direction: SIMD3<Double>,
        center: SIMD3<Double>, halfExtents: SIMD3<Double>
    ) -> FaceHit? {
        let d = simd_normalize(direction)
        var tNear = -Double.infinity
        var tFar = Double.infinity
        var nearAxis = -1
        for axis in 0..<3 {
            let o = origin[axis] - center[axis]
            let h = halfExtents[axis]
            if abs(d[axis]) < 1e-12 {
                if abs(o) > h { return nil }
                continue
            }
            var t0 = (-h - o) / d[axis]
            var t1 = (h - o) / d[axis]
            if t0 > t1 { swap(&t0, &t1) }
            if t0 > tNear {
                tNear = t0
                nearAxis = axis
            }
            tFar = min(tFar, t1)
            if tNear > tFar { return nil }
        }
        guard tNear > 1e-9, nearAxis >= 0 else { return nil }
        var normal = SIMD3<Double>.zero
        normal[nearAxis] = d[nearAxis] > 0 ? -1 : 1
        return FaceHit(point: origin + tNear * d, normal: normal)
    }

    /// The face a ray INSIDE the box strikes next (exit attempt).
    static func interiorHit(
        from origin: SIMD3<Double>, direction: SIMD3<Double>,
        center: SIMD3<Double>, halfExtents: SIMD3<Double>
    ) -> FaceHit? {
        let d = simd_normalize(direction)
        var tExit = Double.infinity
        var exitAxis = -1
        for axis in 0..<3 where abs(d[axis]) > 1e-12 {
            let o = origin[axis] - center[axis]
            let h = halfExtents[axis]
            let t = d[axis] > 0 ? (h - o) / d[axis] : (-h - o) / d[axis]
            if t > 1e-9, t < tExit {
                tExit = t
                exitAxis = axis
            }
        }
        guard exitAxis >= 0, tExit.isFinite else { return nil }
        var normal = SIMD3<Double>.zero
        normal[exitAxis] = d[exitAxis] > 0 ? 1 : -1
        return FaceHit(point: origin + tExit * d, normal: normal)
    }

    /// Traces a ray at the slab: polyline from the origin, through
    /// refraction and any internal reflections, to `escape` beyond the
    /// last surface. A miss flies straight.
    public static func trace(
        from origin: SIMD3<Double>, direction: SIMD3<Double>,
        center: SIMD3<Double>, halfExtents: SIMD3<Double>,
        index n: Double, escape: Double = 0.7, maxInternalBounces: Int = 6
    ) -> [SIMD3<Double>] {
        var d = simd_normalize(direction)
        var points = [origin]

        guard let hit = entry(from: origin, direction: d,
                              center: center, halfExtents: halfExtents) else {
            return [origin, origin + d * escape]
        }
        points.append(hit.point)
        guard let inside = Refraction.refract(
            direction: d, normal: hit.normal, n1: 1.0, n2: n) else {
            points.append(hit.point + Refraction.reflect(direction: d, normal: hit.normal) * escape)
            return points
        }
        d = inside
        var p = hit.point

        for _ in 0..<maxInternalBounces {
            guard let wall = interiorHit(from: p, direction: d,
                                         center: center, halfExtents: halfExtents) else { break }
            p = wall.point
            points.append(p)
            // The refract normal must oppose the ray: the INWARD normal.
            if let out = Refraction.refract(
                direction: d, normal: -wall.normal, n1: n, n2: 1.0) {
                points.append(p + out * escape)
                return points
            }
            // Total internal reflection: the wall is a perfect mirror.
            d = Refraction.reflect(direction: d, normal: wall.normal)
        }
        points.append(p + d * escape)
        return points
    }
}
