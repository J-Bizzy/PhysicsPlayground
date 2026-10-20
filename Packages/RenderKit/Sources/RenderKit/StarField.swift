//
//  StarField.swift
//  RenderKit
//
//  Thousands of stars as ONE mesh: a small quad per star, tangent to a
//  sphere at the star's direction and facing its centre, its corners
//  mapped into one cell of a sprite atlas (a column per colour, a row per
//  brightness — `UnlitMaterial` has no vertex colours, so a star's colour
//  and brightness are WHICH CELL it samples). The quads are assembled off
//  the main thread as plain numbers and written once into a `LowLevelMesh`;
//  nothing about the sky changes per frame but the transform above it.
//

import Foundation
import RealityKit
import simd

public enum StarField {

    /// One star to draw: its direction in the sky's frame, its drawn
    /// half-size as an angle, and the atlas cell it samples.
    public struct Star: Sendable, Equatable {
        public var direction: SIMD3<Float>
        public var halfAngle: Float
        public var column: Int
        public var row: Int
        public init(direction: SIMD3<Float>, halfAngle: Float, column: Int, row: Int) {
            self.direction = direction
            self.halfAngle = halfAngle
            self.column = column
            self.row = row
        }
    }

    /// The atlas a star's cell is read from: `columns` × `rows` cells, each
    /// inset by `gutter` (a fraction of a cell) so mip levels do not bleed
    /// one cell's light into its neighbour.
    public struct Atlas: Sendable, Equatable {
        public var columns: Int
        public var rows: Int
        public var gutter: Float
        public init(columns: Int, rows: Int, gutter: Float) {
            self.columns = columns
            self.rows = rows
            self.gutter = gutter
        }
    }

    /// Tightly packed: three position floats and two UV floats, 20 bytes.
    public struct Vertex: Sendable, Equatable {
        public var x, y, z, u, v: Float
    }

    public struct Geometry: Sendable {
        public var vertices: [Vertex]
        public var indices: [UInt16]
        public var radius: Float
    }

    /// The quads, as numbers. 16-bit indices hold 16,384 stars.
    public static func assemble(_ stars: [Star], radius: Float, atlas: Atlas) -> Geometry {
        let count = min(stars.count, 65_536 / 4)
        var vertices: [Vertex] = []
        vertices.reserveCapacity(count * 4)
        var indices: [UInt16] = []
        indices.reserveCapacity(count * 6)
        for star in stars.prefix(count) {
            let d = simd_normalize(star.direction)
            // The local east and north at the star: an orthonormal pair
            // tangent to the sphere.
            let reference: SIMD3<Float> = abs(d.z) < 0.99 ? [0, 0, 1] : [1, 0, 0]
            let east = simd_normalize(simd_cross(reference, d))
            let north = simd_cross(d, east)
            let half = radius * tan(star.halfAngle)
            let centre = d * radius
            let cellWidth = 1 / Float(atlas.columns), cellHeight = 1 / Float(atlas.rows)
            let inset = atlas.gutter
            let u0 = (Float(star.column) + inset) * cellWidth
            let u1 = (Float(star.column + 1) - inset) * cellWidth
            // Row 0 is the top of the atlas image; a texture's v runs up.
            let v1 = 1 - (Float(star.row) + inset) * cellHeight
            let v0 = 1 - (Float(star.row + 1) - inset) * cellHeight
            let base = UInt16(vertices.count)
            for (e, n, u, v) in [(-1, -1, u0, v0), (1, -1, u1, v0), (1, 1, u1, v1), (-1, 1, u0, v1)]
            as [(Float, Float, Float, Float)] {
                let p = centre + half * (e * east + n * north)
                vertices.append(Vertex(x: p.x, y: p.y, z: p.z, u: u, v: v))
            }
            // Wound to face the centre, where the wearer stands.
            indices += [base, base + 2, base + 1, base, base + 3, base + 2]
        }
        return Geometry(vertices: vertices, indices: indices, radius: radius)
    }

    /// The assembled quads as a mesh, written once.
    @MainActor
    public static func mesh(_ geometry: Geometry) -> MeshResource? {
        guard !geometry.vertices.isEmpty else { return nil }
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = geometry.vertices.count
        descriptor.indexCapacity = geometry.indices.count
        descriptor.indexType = .uint16
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
            .init(semantic: .uv0, format: .float2, layoutIndex: 0,
                  offset: MemoryLayout<Float>.stride * 3),
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
        guard let mesh = try? LowLevelMesh(descriptor: descriptor) else { return nil }
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            geometry.vertices.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        mesh.withUnsafeMutableIndices { raw in
            geometry.indices.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        let r = geometry.radius * 1.01
        mesh.parts.replaceAll([LowLevelMesh.Part(
            indexCount: geometry.indices.count, topology: .triangle,
            bounds: BoundingBox(min: [-r, -r, -r], max: [r, r, r]))])
        return try? MeshResource(from: mesh)
    }
}
