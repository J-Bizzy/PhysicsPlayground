//
//  MarchingSquares.swift
//  PhysicsCore — Math: iso-contours of a 2-D scalar field, as line segments.
//  Standard marching squares, linear interpolation along crossed edges.
//

import Foundation
import simd

public enum MarchingSquares {
    /// One straight piece of a contour, in the plane's own 2-D coords.
    public struct Segment: Equatable, Sendable {
        public var a: SIMD2<Double>
        public var b: SIMD2<Double>
        public init(a: SIMD2<Double>, b: SIMD2<Double>) {
            self.a = a
            self.b = b
        }
    }

    /// Extracts the contour `scalar == level` over an axis-aligned rectangle
    /// as unordered segments. `resolution` = cells per side, cost O(resolution²).
    public static func contour(
        level: Double,
        scalar: (SIMD2<Double>) -> Double,
        center: SIMD2<Double>,
        extents: SIMD2<Double>,
        resolution: Int
    ) -> [Segment] {
        guard resolution >= 1 else { return [] }
        let n = resolution
        let origin = center - extents / 2
        let step = SIMD2(extents.x / Double(n), extents.y / Double(n))

        var values = [Double](repeating: 0, count: (n + 1) * (n + 1))
        for j in 0...n {
            for i in 0...n {
                let point = origin + SIMD2(Double(i) * step.x, Double(j) * step.y)
                values[j * (n + 1) + i] = scalar(point)
            }
        }
        func value(_ i: Int, _ j: Int) -> Double { values[j * (n + 1) + i] }
        func point(_ i: Int, _ j: Int) -> SIMD2<Double> {
            origin + SIMD2(Double(i) * step.x, Double(j) * step.y)
        }
        /// Where the level crosses the segment between two corners.
        func crossing(_ p: SIMD2<Double>, _ vp: Double,
                      _ q: SIMD2<Double>, _ vq: Double) -> SIMD2<Double> {
            let denominator = vq - vp
            guard abs(denominator) > 1e-15 else { return (p + q) / 2 }
            let t = min(max((level - vp) / denominator, 0), 1)
            return p + (q - p) * t
        }

        var segments: [Segment] = []
        for j in 0..<n {
            for i in 0..<n {
                // Corner order (CCW from bottom-left) must match the bitmask table below.
                let p0 = point(i, j),       v0 = value(i, j)
                let p1 = point(i + 1, j),   v1 = value(i + 1, j)
                let p2 = point(i + 1, j + 1), v2 = value(i + 1, j + 1)
                let p3 = point(i, j + 1),   v3 = value(i, j + 1)

                var code = 0
                if v0 >= level { code |= 1 }
                if v1 >= level { code |= 2 }
                if v2 >= level { code |= 4 }
                if v3 >= level { code |= 8 }
                if code == 0 || code == 15 { continue }

                let bottom = crossing(p0, v0, p1, v1)
                let right  = crossing(p1, v1, p2, v2)
                let top    = crossing(p3, v3, p2, v2)
                let left   = crossing(p0, v0, p3, v3)

                switch code {
                case 1, 14: segments.append(Segment(a: left, b: bottom))
                case 2, 13: segments.append(Segment(a: bottom, b: right))
                case 3, 12: segments.append(Segment(a: left, b: right))
                case 4, 11: segments.append(Segment(a: right, b: top))
                case 6, 9:  segments.append(Segment(a: bottom, b: top))
                case 7, 8:  segments.append(Segment(a: left, b: top))
                case 5, 10:
                    // Ambiguous saddle: the cell's mean decides how the branches connect.
                    let mean = (v0 + v1 + v2 + v3) / 4
                    let joined = (code == 5) == (mean >= level)
                    if joined {
                        segments.append(Segment(a: left, b: top))
                        segments.append(Segment(a: bottom, b: right))
                    } else {
                        segments.append(Segment(a: left, b: bottom))
                        segments.append(Segment(a: right, b: top))
                    }
                default: break
                }
            }
        }
        return segments
    }

    /// Chains segments into polylines by welding shared endpoints
    /// (`tolerance` = weld distance), so a contour sweeps as one tube.
    public static func chain(_ segments: [Segment],
                             tolerance: Double = 1e-6) -> [[SIMD2<Double>]] {
        guard !segments.isEmpty else { return [] }

        // Tolerance-grid bucketing keeps welding O(n); the 3×3 scan covers
        // points straddling a bucket boundary.
        let cell = max(tolerance, 1e-12)
        var buckets: [SIMD2<Int>: [Int]] = [:]
        var vertices: [SIMD2<Double>] = []

        func bucket(_ p: SIMD2<Double>) -> SIMD2<Int> {
            SIMD2(Int((p.x / cell).rounded(.down)), Int((p.y / cell).rounded(.down)))
        }
        func vertexID(_ p: SIMD2<Double>) -> Int {
            let home = bucket(p)
            for dj in -1...1 {
                for di in -1...1 {
                    for candidate in buckets[home &+ SIMD2(di, dj)] ?? [] {
                        if simd_distance(vertices[candidate], p) <= tolerance {
                            return candidate
                        }
                    }
                }
            }
            let id = vertices.count
            vertices.append(p)
            buckets[home, default: []].append(id)
            return id
        }

        var edges: [(a: Int, b: Int)] = []
        var incident: [Int: [Int]] = [:]
        for segment in segments {
            let a = vertexID(segment.a), b = vertexID(segment.b)
            guard a != b else { continue }          // drop degenerate stubs
            let index = edges.count
            edges.append((a, b))
            incident[a, default: []].append(index)
            incident[b, default: []].append(index)
        }
        guard !edges.isEmpty else { return [] }

        var usedEdge = [Bool](repeating: false, count: edges.count)

        /// Walks as far as possible from `vertex`, consuming edges.
        func walk(from start: Int) -> [Int] {
            var path = [start]
            var current = start
            while true {
                guard let next = (incident[current] ?? []).first(where: { !usedEdge[$0] })
                else { break }
                usedEdge[next] = true
                let edge = edges[next]
                current = edge.a == current ? edge.b : edge.a
                path.append(current)
                if current == start { break }        // closed the loop
            }
            return path
        }

        var polylines: [[SIMD2<Double>]] = []

        // Open contours first, seeded at odd-degree endpoints, so an open
        // curve is never started mid-span and split in two.
        for (vertex, list) in incident where list.count % 2 == 1 {
            guard list.contains(where: { !usedEdge[$0] }) else { continue }
            let path = walk(from: vertex)
            if path.count >= 2 { polylines.append(path.map { vertices[$0] }) }
        }
        for index in edges.indices where !usedEdge[index] {
            let path = walk(from: edges[index].a)
            if path.count >= 2 { polylines.append(path.map { vertices[$0] }) }
        }
        return polylines
    }
}
