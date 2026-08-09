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

    /// Thins polylines that are sampled far finer than the tube they
    /// will become, WITHOUT rounding off the corners.
    ///
    /// A field-line tracer integrates at a step chosen for the physics,
    /// not for the mesh: Magnetism walks 8 mm steps to build a 1.6 mm
    /// tube, so five points in six pay for vertices nobody can see. But
    /// a plain "keep every Nth point" flattens exactly the places that
    /// need the samples — loops crowd tightest where they wrap a pole,
    /// and that is the shape a reader is reading.
    ///
    /// So the rule is distance OR turn, whichever comes first: a point
    /// survives if it is `spacing` along the line from the last one
    /// kept, or if the heading has swung `maximumTurn` since then.
    /// Straight far-field runs — which is where the vertex count
    /// actually lives — thin out by the full ratio; a tight near-pole
    /// arc keeps every point it needs and no more. Ends are always
    /// kept, so a loop still closes where it closed.
    ///
    /// - Parameters:
    ///   - spacing: metres of arc between kept points on a straight run.
    ///   - maximumTurn: radians of heading change that forces a keep.
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
