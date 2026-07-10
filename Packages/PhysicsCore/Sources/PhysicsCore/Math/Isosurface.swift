//
//  Isosurface.swift
//  PhysicsCore — Math
//
//  Domain-agnostic isosurface extraction: triangulates the set of points
//  where any scalar field f(r) equals a chosen level, via marching
//  tetrahedra. Equipotential shells, interference surfaces, and density
//  contours are all isosurfaces — modules supply the scalar closure and an
//  outward-direction closure used to orient triangle winding.
//
//  Method: the region is divided into a uniform grid of cubes, each cube
//  into six tetrahedra sharing a main diagonal. Within a tetrahedron the
//  field is treated as linear, so the f = level surface cuts it in one of
//  only a few simple ways (a triangle or a quad), with crossing points
//  found by linear interpolation along the edges. It's the small-table
//  cousin of marching cubes: slightly more triangles, far simpler case
//  analysis, and no topological ambiguities.
//

import Foundation
import simd

public enum Isosurface {
    /// Flat triangle list (every 3 consecutive points form one triangle) for
    /// the isosurface f = `level` inside the box. Triangles are wound so the
    /// right-hand-rule normal points along `outwardDirection`.
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

        // Sample f on the (n+1)³ lattice once; cells then just look values up.
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

        // Cube corners (unit offsets) and the 6-tetrahedron decomposition,
        // every tetrahedron sharing the 0→6 main diagonal.
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
                    // Surface can't pass through a cube that's all one side.
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
}
