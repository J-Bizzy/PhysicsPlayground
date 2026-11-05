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

/// The CPU side of a tube mesh — buildable on any thread, uploaded on
/// the main actor. Lets GeometryPipeline workers do the vertex math.
public struct TubeBuffers: Sendable {
    public var positions: [SIMD3<Float>] = []
    public var normals: [SIMD3<Float>] = []
    public var indices: [UInt32] = []
    public var isEmpty: Bool { indices.isEmpty }

    public init(positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [],
                indices: [UInt32] = []) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
    }
}

@MainActor public enum TubeMesh {
    /// Convenience for callers already on the main actor.
    public static func tube(lines: [[SIMD3<Float>]], radius: Float = 0.0016, sides: Int = 5) -> MeshResource? {
        mesh(from: buffers(lines: lines, radius: radius, sides: sides))
    }

    /// Uploads prebuilt buffers as a MeshResource (main actor: resource
    /// creation touches RealityKit).
    public static func mesh(from buffers: TubeBuffers) -> MeshResource? {
        guard !buffers.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: "tubes")
        descriptor.positions = MeshBuffer(buffers.positions)
        descriptor.normals = MeshBuffer(buffers.normals)
        descriptor.primitives = .triangles(buffers.indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Thins polylines sampled far finer than the tube they will become,
    /// without rounding off the corners: a point survives if it is
    /// `spacing` along the line from the last one kept, or if the heading
    /// has swung `maximumTurn` since then. Straight far-field runs thin by
    /// the full ratio; a tight arc keeps every point it needs. Ends are
    /// always kept, so a loop still closes.
    public nonisolated static func decimated(
        _ lines: [[SIMD3<Float>]], spacing: Float, maximumTurn: Float = .pi / 18
    ) -> [[SIMD3<Float>]] {
        guard spacing > 0 else { return lines }
        let cosineLimit = cos(maximumTurn)
        return lines.map { line in
            guard line.count > 2 else { return line }
            var kept: [SIMD3<Float>] = [line[0]]
            var walked: Float = 0
            // Heading as of the last kept point; zero until we have one.
            var reference = SIMD3<Float>.zero

            for index in 1..<(line.count - 1) {
                let step = line[index] - line[index - 1]
                let length = simd_length(step)
                guard length > 1e-9 else { continue }
                walked += length
                let heading = step / length

                let turned = reference == .zero
                    ? false
                    : simd_dot(heading, reference) < cosineLimit
                if walked >= spacing || turned {
                    kept.append(line[index])
                    walked = 0
                    reference = heading
                } else if reference == .zero {
                    reference = heading
                }
            }
            kept.append(line[line.count - 1])
            return kept
        }
    }

    /// Arrowheads riding a set of lines, appended to that set's own buffers
    /// so they draw with it as one mesh instead of an entity each (2026-11-03:
    /// Electric Fields' opening dipole was 185 cones, 185 draws). A cone of
    /// `sides` facets is centred on each point, its apex along its direction,
    /// wound to face outward.
    public nonisolated static func appendCones(
        to buffers: inout TubeBuffers, at points: [SIMD3<Float>],
        directions: [SIMD3<Float>], height: Float, radius: Float, sides: Int = 12
    ) {
        for (point, direction) in zip(points, directions) {
            let length = simd_length(direction)
            guard length > 1e-9 else { continue }
            let tangent = direction / length
            let reference: SIMD3<Float> = abs(tangent.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
            let side = simd_normalize(simd_cross(tangent, reference))
            let up = simd_cross(tangent, side)
            let base = point - tangent * (height / 2)
            let apex = point + tangent * (height / 2)

            // The slanted face: a ring round the base and one apex.
            let ring = UInt32(buffers.positions.count)
            for s in 0..<sides {
                let angle = 2 * Float.pi * Float(s) / Float(sides)
                let out = cos(angle) * side + sin(angle) * up
                buffers.positions.append(base + radius * out)
                buffers.normals.append(simd_normalize(height * out + radius * tangent))
            }
            let tip = UInt32(buffers.positions.count)
            buffers.positions.append(apex)
            buffers.normals.append(tangent)
            // The base, facing back down the line.
            let cap = UInt32(buffers.positions.count)
            buffers.positions.append(base)
            buffers.normals.append(-tangent)
            for s in 0..<sides {
                let angle = 2 * Float.pi * Float(s) / Float(sides)
                buffers.positions.append(base + radius * (cos(angle) * side + sin(angle) * up))
                buffers.normals.append(-tangent)
            }
            for s in 0..<UInt32(sides) {
                let next = (s + 1) % UInt32(sides)
                buffers.indices += [ring + s, ring + next, tip]
                buffers.indices += [cap, cap + 1 + next, cap + 1 + s]
            }
        }
    }

    /// Pure vertex math — safe on any thread.
    public nonisolated static func buffers(
        lines: [[SIMD3<Float>]], radius: Float = 0.0016, sides: Int = 5
    ) -> TubeBuffers {
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

        return TubeBuffers(positions: positions, normals: normals, indices: indices)
    }
}
