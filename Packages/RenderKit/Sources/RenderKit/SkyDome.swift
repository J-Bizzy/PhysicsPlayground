//
//  SkyDome.swift
//  RenderKit
//
//  An inward-facing sphere whose texture coordinates are a sky's own: u is
//  right ascension / 2π, v is (declination + 90°) / 180° — an
//  equirectangular image of the celestial sphere maps onto it as drawn. Its
//  frame is the equatorial one (x̂ toward the equinox, ẑ toward the north
//  celestial pole); whoever mounts it turns that into the room.
//

import Foundation
import RealityKit
import simd

public enum SkyDome {

    @MainActor
    public static func mesh(radius: Float, longitudeSegments: Int = 128,
                            latitudeSegments: Int = 64) -> MeshResource? {
        let columns = max(longitudeSegments, 8), rows = max(latitudeSegments, 4)
        var positions: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        positions.reserveCapacity((columns + 1) * (rows + 1))
        for row in 0...rows {
            let v = Float(row) / Float(rows)
            let declination = (v - 0.5) * .pi
            for column in 0...columns {
                let u = Float(column) / Float(columns)
                let ascension = u * 2 * .pi
                positions.append(radius * SIMD3(cos(declination) * cos(ascension),
                                                cos(declination) * sin(ascension),
                                                sin(declination)))
                coordinates.append(SIMD2(u, v))
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(columns * rows * 6)
        let stride = UInt32(columns + 1)
        for row in 0..<UInt32(rows) {
            for column in 0..<UInt32(columns) {
                let a = row * stride + column, b = a + 1
                let c = a + stride, d = c + 1
                // Wound to face inward.
                indices += [a, c, b, b, c, d]
            }
        }
        var descriptor = MeshDescriptor(name: "sky-dome")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
