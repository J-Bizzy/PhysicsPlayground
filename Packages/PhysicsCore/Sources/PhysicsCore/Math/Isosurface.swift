//
//  Isosurface.swift
//  PhysicsCore — Math: isosurface extraction f(r) = level via marching
//  tetrahedra (6 tets/cube, linear edge interpolation, no ambiguities).
//

import Foundation
import simd

public enum Isosurface {
    /// Flat triangle list (3 consecutive points per triangle) for f = `level`
    /// inside the box, wound so the RH-rule normal points along `outwardDirection`.
    public static func triangles(
        level: Double,
        scalar: (SIMD3<Double>) -> Double,
        outwardDirection: (SIMD3<Double>) -> SIMD3<Double>,
        center: SIMD3<Double>,
        extents: SIMD3<Double>,
        resolution: Int = 24
    ) -> [SIMD3<Double>] {
        guard resolution >= 2 else { return [] }

        let n = resolution
        let lower = center - extents / 2
        let spacing = extents / Double(n)

        var values = [Double]()
        values.reserveCapacity((n + 1) * (n + 1) * (n + 1))
        for i in 0...n {
            for j in 0...n {
                for k in 0...n {
                    values.append(scalar(lower + spacing * SIMD3(Double(i), Double(j), Double(k))))
                }
            }
        }
        func value(_ i: Int, _ j: Int, _ k: Int) -> Double {
            values[(i * (n + 1) + j) * (n + 1) + k]
        }

        // 6-tetrahedron decomposition; every tet must share the 0→6 main diagonal.
        let cornerOffsets: [SIMD3<Int>] = [
            [0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
            [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1],
        ]
        let tetrahedra = [
            [0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6],
            [0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6],
        ]

        var triangles: [SIMD3<Double>] = []
        var cornerPoints = [SIMD3<Double>](repeating: .zero, count: 8)
        var cornerValues = [Double](repeating: 0, count: 8)

        for i in 0..<n {
            for j in 0..<n {
                for k in 0..<n {
                    var anyAbove = false
                    var anyBelow = false
                    for (c, offset) in cornerOffsets.enumerated() {
                        let gi = i + offset.x, gj = j + offset.y, gk = k + offset.z
                        cornerValues[c] = value(gi, gj, gk)
                        cornerPoints[c] = lower + spacing * SIMD3(Double(gi), Double(gj), Double(gk))
                        if cornerValues[c] > level { anyAbove = true } else { anyBelow = true }
                    }
                    guard anyAbove && anyBelow else { continue }

                    for tet in tetrahedra {
                        march(
                            tetPoints: tet.map { cornerPoints[$0] },
                            tetValues: tet.map { cornerValues[$0] },
                            level: level,
                            outwardDirection: outwardDirection,
                            into: &triangles
                        )
                    }
                }
            }
        }
        return triangles
    }

    /// Emits 0–2 triangles for one tetrahedron.
    private static func march(
        tetPoints: [SIMD3<Double>],
        tetValues: [Double],
        level: Double,
        outwardDirection: (SIMD3<Double>) -> SIMD3<Double>,
        into triangles: inout [SIMD3<Double>]
    ) {
        let above = (0..<4).filter { tetValues[$0] > level }
        let below = (0..<4).filter { tetValues[$0] <= level }

        /// Point where the surface crosses the edge between corners a and b.
        func crossing(_ a: Int, _ b: Int) -> SIMD3<Double> {
            let va = tetValues[a], vb = tetValues[b]
            let t = abs(vb - va) < 1e-300 ? 0.5 : (level - va) / (vb - va)
            return tetPoints[a] + t * (tetPoints[b] - tetPoints[a])
        }

        func appendOriented(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) {
            let windingNormal = simd_cross(b - a, c - a)
            let reference = outwardDirection((a + b + c) / 3)
            if simd_dot(windingNormal, reference) < 0 {
                triangles.append(contentsOf: [a, c, b])
            } else {
                triangles.append(contentsOf: [a, b, c])
            }
        }

        switch above.count {
        case 1:
            let a = above[0]
            appendOriented(crossing(a, below[0]), crossing(a, below[1]), crossing(a, below[2]))
        case 3:
            let b = below[0]
            appendOriented(crossing(b, above[0]), crossing(b, above[1]), crossing(b, above[2]))
        case 2:
            // Surface is a quad: split into two triangles.
            let (a0, a1) = (above[0], above[1])
            let (b0, b1) = (below[0], below[1])
            let p0 = crossing(a0, b0)
            let p1 = crossing(a0, b1)
            let p2 = crossing(a1, b1)
            let p3 = crossing(a1, b0)
            appendOriented(p0, p1, p2)
            appendOriented(p0, p2, p3)
        default:
            break  // 0 or 4: no crossing
        }
    }

    // MARK: Indexed, welded, many levels

    /// One level's surface as an indexed mesh: each vertex shared by every
    /// triangle that meets it, so the surface is closed and smooth-shaded.
    public struct Mesh: Sendable, Equatable {
        public var level: Double
        public var positions: [SIMD3<Float>] = []
        /// Unit normals from the scalar's exact gradient, not from the
        /// facets, so a coarse grid still shades as a smooth surface.
        public var normals: [SIMD3<Float>] = []
        public var indices: [UInt32] = []

        public var triangleCount: Int { indices.count / 3 }

        /// Every edge in exactly two triangles: the surface closes inside
        /// the box. An open one was cut by the box's faces, and the cut is
        /// the box's shape, not the field's.
        public var isClosed: Bool {
            guard !indices.isEmpty else { return false }
            var edges: [UInt64: Int] = [:]
            for t in Swift.stride(from: 0, to: indices.count, by: 3) {
                for (a, b) in [(indices[t], indices[t + 1]), (indices[t + 1], indices[t + 2]),
                               (indices[t + 2], indices[t])] {
                    edges[UInt64(min(a, b)) << 32 | UInt64(max(a, b)), default: 0] += 1
                }
            }
            return edges.values.allSatisfy { $0 == 2 }
        }
    }

    /// The surfaces f = level for every level, from ONE sampling of the grid.
    /// Vertices are welded by the grid edge they lie on, so each surface is a
    /// closed mesh wherever it does not leave the box. Each normal is
    /// −sign(level)·∇f, normalised: it faces the way |f| falls, out of the
    /// peak (or trough) the surface surrounds — for a potential, out of the
    /// charge whatever its sign. Each triangle is wound to face the way its
    /// normals do. Levels are meshed innermost first (largest |level|),
    /// and meshing stops before `maxTriangles` would be passed: what is
    /// dropped is the outermost, largest surfaces.
    ///
    /// Interpolating along an edge puts a vertex where a LINEAR f would
    /// cross the level, and a potential is far from linear near its charge:
    /// a 3 cm cell bends a 10 cm sphere into a visible ripple. So each
    /// vertex then takes `refinement` Newton steps along the exact
    /// gradient, x ← x − (f − level)∇f/|∇f|², each held to half a cell,
    /// which lands it on the true surface to well under a micrometre.
    public static func meshes(
        levels: [Double],
        scalar: (SIMD3<Double>) -> Double,
        gradient: (SIMD3<Double>) -> SIMD3<Double>,
        center: SIMD3<Double>,
        extents: SIMD3<Double>,
        resolution: Int = 40,
        maxTriangles: Int = .max,
        refinement: Int = 3
    ) -> [Mesh] {
        guard resolution >= 2, !levels.isEmpty else { return [] }
        let n = resolution
        let lower = center - extents / 2
        let spacing = extents / Double(n)
        let reach = spacing.min() / 2
        let stride = n + 1
        func index(_ i: Int, _ j: Int, _ k: Int) -> Int { (i * stride + j) * stride + k }
        func point(_ flat: Int) -> SIMD3<Double> {
            let k = flat % stride, j = (flat / stride) % stride, i = flat / (stride * stride)
            return lower + spacing * SIMD3(Double(i), Double(j), Double(k))
        }
        var values = [Double](repeating: 0, count: stride * stride * stride)
        for i in 0...n {
            for j in 0...n {
                for k in 0...n {
                    values[index(i, j, k)] = scalar(lower + spacing * SIMD3(Double(i), Double(j), Double(k)))
                }
            }
        }

        let cornerOffsets: [SIMD3<Int>] = [
            [0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
            [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1],
        ]
        let tetrahedra = [
            [0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6],
            [0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6],
        ]

        var meshes: [Mesh] = []
        var total = 0
        for level in levels.sorted(by: { abs($0) > abs($1) }) {
            var mesh = Mesh(level: level)
            var welded: [UInt64: UInt32] = [:]
            let facing: Double = level < 0 ? 1 : -1

            /// The vertex where the surface crosses the grid edge a–b.
            func vertex(_ a: Int, _ b: Int) -> UInt32 {
                let key = a < b ? UInt64(a) << 32 | UInt64(b) : UInt64(b) << 32 | UInt64(a)
                if let existing = welded[key] { return existing }
                let va = values[a], vb = values[b]
                let t = abs(vb - va) < 1e-300 ? 0.5 : (level - va) / (vb - va)
                var p = point(a) + t * (point(b) - point(a))
                for _ in 0..<refinement {
                    let slope = gradient(p)
                    let steepness = simd_length_squared(slope)
                    guard steepness > 1e-300 else { break }
                    var step = (scalar(p) - level) * slope / steepness
                    let length = simd_length(step)
                    if length > reach { step *= reach / length }
                    p -= step
                }
                var normal = gradient(p) * facing
                let length = simd_length(normal)
                normal = length > 1e-300 ? normal / length : SIMD3(0, 1, 0)
                let id = UInt32(mesh.positions.count)
                mesh.positions.append(SIMD3<Float>(p))
                mesh.normals.append(SIMD3<Float>(normal))
                welded[key] = id
                return id
            }

            func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
                let pa = mesh.positions[Int(a)], pb = mesh.positions[Int(b)], pc = mesh.positions[Int(c)]
                // A sliver of no area is kept, not dropped: its edges are
                // shared with its neighbours, and dropping it would open
                // the surface in the index even where no gap shows.
                let face = simd_cross(pb - pa, pc - pa)
                let wanted = mesh.normals[Int(a)] + mesh.normals[Int(b)] + mesh.normals[Int(c)]
                if simd_dot(face, wanted) >= 0 {
                    mesh.indices += [a, b, c]
                } else {
                    mesh.indices += [a, c, b]
                }
            }

            for i in 0..<n {
                for j in 0..<n {
                    for k in 0..<n {
                        var corners = [Int](repeating: 0, count: 8)
                        var anyAbove = false, anyBelow = false
                        for (c, offset) in cornerOffsets.enumerated() {
                            let flat = index(i + offset.x, j + offset.y, k + offset.z)
                            corners[c] = flat
                            if values[flat] > level { anyAbove = true } else { anyBelow = true }
                        }
                        guard anyAbove && anyBelow else { continue }
                        for tet in tetrahedra {
                            let grid = tet.map { corners[$0] }
                            let above = grid.filter { values[$0] > level }
                            let below = grid.filter { values[$0] <= level }
                            switch above.count {
                            case 1:
                                triangle(vertex(above[0], below[0]), vertex(above[0], below[1]),
                                         vertex(above[0], below[2]))
                            case 3:
                                triangle(vertex(below[0], above[0]), vertex(below[0], above[1]),
                                         vertex(below[0], above[2]))
                            case 2:
                                let p0 = vertex(above[0], below[0]), p1 = vertex(above[0], below[1])
                                let p2 = vertex(above[1], below[1]), p3 = vertex(above[1], below[0])
                                triangle(p0, p1, p2)
                                triangle(p0, p2, p3)
                            default:
                                break
                            }
                        }
                    }
                }
            }
            guard total + mesh.triangleCount <= maxTriangles else { break }
            total += mesh.triangleCount
            if mesh.triangleCount > 0 { meshes.append(mesh) }
        }
        return meshes
    }
}
