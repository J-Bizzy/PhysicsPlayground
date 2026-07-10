//
//  TubeMesh.swift
//  RenderKit
//
//  Builds one MeshResource containing any set of polylines as thin tubes.
//  A single mesh in a single ModelEntity keeps the draw count at 1 no
//  matter how many lines there are — far cheaper than per-segment entities.
//  Field lines, orbit trails, and light rays all render through this.
//
//  Each polyline becomes a tube: a ring of `sides` vertices is placed
//  around every point, oriented perpendicular to the local tangent, and
//  consecutive rings are stitched with triangles.
//

import Foundation
import RealityKit
import simd

@MainActor public enum TubeMesh {
    public static func tube(lines: [[SIMD3<Float>]], radius: Float = 0.0016, sides: Int = 5) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for line in lines where line.count >= 2 {
            let ringStart = UInt32(positions.count)

            for (i, point) in line.enumerated() {
                // Central-difference tangent (one-sided at the ends).
                let prev = line[max(i - 1, 0)]
                let next = line[min(i + 1, line.count - 1)]
                var tangent = next - prev
                let tangentLength = simd_length(tangent)
                guard tangentLength > 1e-7 else { continue }
                tangent /= tangentLength

                // A stable perpendicular frame for the ring.
                let reference: SIMD3<Float> = abs(tangent.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
                let side = simd_normalize(simd_cross(tangent, reference))
                let up = simd_cross(tangent, side)

                for s in 0..<sides {
                    let angle = 2 * Float.pi * Float(s) / Float(sides)
                    let ringDirection = cos(angle) * side + sin(angle) * up
                    positions.append(point + radius * ringDirection)
                    normals.append(ringDirection)
                }
            }

            let ringCount = (positions.count - Int(ringStart)) / sides
            guard ringCount >= 2 else { continue }

            for ring in 0..<(ringCount - 1) {
                let a = ringStart + UInt32(ring * sides)
                let b = a + UInt32(sides)
                for s in 0..<UInt32(sides) {
                    let sNext = (s + 1) % UInt32(sides)
                    indices += [a + s, b + s, a + sNext]
                    indices += [a + sNext, b + s, b + sNext]
                }
            }
        }

        guard !indices.isEmpty else { return nil }

        var descriptor = MeshDescriptor(name: "tubes")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
