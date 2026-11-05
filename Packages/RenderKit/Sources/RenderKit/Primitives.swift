//
//  Primitives.swift
//  RenderKit
//
//  Shared primitive meshes and colliders, made once per shape. RealityKit
//  builds a fresh resource for every `generate*` call, and each build is a
//  round trip that blocks the main thread on the engine queue — a bench
//  holds hundreds of identical spheres, plates and terminals, and entering
//  a lab paid for every one. Resources are immutable, so sharing is free.
//

import Foundation
import RealityKit

@MainActor
public enum Primitives {

    // MARK: Meshes

    public static func sphere(radius: Float) -> MeshResource {
        mesh(.init("sphere", radius)) { .generateSphere(radius: radius) }
    }

    /// A sphere of `segments` facets around and half as many pole to pole,
    /// for a small thing drawn often: `generateSphere` is about 8 000
    /// triangles at any radius, and Electric Fields' charges, halo and wells
    /// were 30 000 of its opening's 84 000 (2026-11-03). Forty around is
    /// 1 600 triangles, smooth at a charge's 3 cm.
    public static func sphere(radius: Float, segments: Int) -> MeshResource {
        mesh(.init("sphere", radius, Float(segments))) {
            let around = max(segments, 6)
            let rings = max(around / 2, 3)
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var coordinates: [SIMD2<Float>] = []
            for ring in 0...rings {
                let v = Float(ring) / Float(rings)
                let polar = v * .pi
                for step in 0...around {
                    let u = Float(step) / Float(around)
                    let azimuth = u * 2 * .pi
                    let normal = SIMD3<Float>(sin(polar) * cos(azimuth), cos(polar),
                                              sin(polar) * sin(azimuth))
                    positions.append(normal * radius)
                    normals.append(normal)
                    coordinates.append(SIMD2(u, 1 - v))
                }
            }
            let stride = UInt32(around + 1)
            var indices: [UInt32] = []
            for ring in 0..<UInt32(rings) {
                for step in 0..<UInt32(around) {
                    let a = ring * stride + step, b = a + 1, c = a + stride, d = c + 1
                    // Wound to face outward; the poles' slivers are skipped.
                    if ring > 0 { indices += [a, b, c] }
                    if ring < UInt32(rings) - 1 { indices += [b, d, c] }
                }
            }
            var descriptor = MeshDescriptor(name: "sphere")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates)
            descriptor.primitives = .triangles(indices)
            return (try? MeshResource.generate(from: [descriptor]))
                ?? .generateSphere(radius: radius)
        }
    }

    /// A flat bar with rounded corners, `segments` facets to a corner: its
    /// faces flat and its depth square — a sign's stroke, in 80 triangles
    /// where a rounded `generateBox` is 13 000 at any size (2026-11-03).
    public static func roundedBar(size: SIMD3<Float>, cornerRadius: Float,
                                  segments: Int = 4) -> MeshResource {
        mesh(.init("roundedBar", size.x, size.y, size.z, cornerRadius, Float(segments))) {
            let half = size / 2
            let radius = min(cornerRadius, half.x, half.y)
            // The outline, counter-clockwise seen from +z, a quarter arc at
            // each corner, with the outward normal of each point.
            var outline: [(point: SIMD2<Float>, normal: SIMD2<Float>)] = []
            let centres: [SIMD2<Float>] = [[half.x - radius, half.y - radius],
                                           [-(half.x - radius), half.y - radius],
                                           [-(half.x - radius), -(half.y - radius)],
                                           [half.x - radius, -(half.y - radius)]]
            for (corner, centre) in centres.enumerated() {
                for step in 0...max(segments, 1) {
                    let angle = (Float(corner) + Float(step) / Float(max(segments, 1))) * .pi / 2
                    let normal = SIMD2<Float>(cos(angle), sin(angle))
                    outline.append((centre + radius * normal, normal))
                }
            }
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var indices: [UInt32] = []
            let count = UInt32(outline.count)
            // The two faces, each fanned from its centre.
            for (z, facing) in [(half.z, Float(1)), (-half.z, Float(-1))] {
                let centre = UInt32(positions.count)
                positions.append([0, 0, z])
                normals.append([0, 0, facing])
                for entry in outline {
                    positions.append([entry.point.x, entry.point.y, z])
                    normals.append([0, 0, facing])
                }
                for i in 0..<count {
                    let a = centre + 1 + i, b = centre + 1 + (i + 1) % count
                    indices += facing > 0 ? [centre, a, b] : [centre, b, a]
                }
            }
            // The rim, front ring then back ring.
            let rim = UInt32(positions.count)
            for z in [half.z, -half.z] {
                for entry in outline {
                    positions.append([entry.point.x, entry.point.y, z])
                    normals.append([entry.normal.x, entry.normal.y, 0])
                }
            }
            for i in 0..<count {
                let front = rim + i, frontNext = rim + (i + 1) % count
                let back = front + count, backNext = frontNext + count
                indices += [front, back, frontNext, frontNext, back, backNext]
            }
            var descriptor = MeshDescriptor(name: "rounded-bar")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(indices)
            return (try? MeshResource.generate(from: [descriptor]))
                ?? .generateBox(size: size, cornerRadius: cornerRadius)
        }
    }

    public static func box(size: SIMD3<Float>, cornerRadius: Float = 0) -> MeshResource {
        mesh(.init("box", size.x, size.y, size.z, cornerRadius)) {
            .generateBox(size: size, cornerRadius: cornerRadius)
        }
    }

    public static func box(width: Float, height: Float, depth: Float,
                           cornerRadius: Float = 0) -> MeshResource {
        box(size: [width, height, depth], cornerRadius: cornerRadius)
    }

    /// A vertical plane in XY, facing +Z.
    public static func plane(width: Float, height: Float,
                             cornerRadius: Float = 0) -> MeshResource {
        mesh(.init("planeXY", width, height, cornerRadius)) {
            .generatePlane(width: width, height: height, cornerRadius: cornerRadius)
        }
    }

    /// A horizontal plane in XZ, facing +Y.
    public static func plane(width: Float, depth: Float,
                             cornerRadius: Float = 0) -> MeshResource {
        mesh(.init("planeXZ", width, depth, cornerRadius)) {
            .generatePlane(width: width, depth: depth, cornerRadius: cornerRadius)
        }
    }

    public static func cylinder(height: Float, radius: Float) -> MeshResource {
        mesh(.init("cylinder", height, radius)) {
            .generateCylinder(height: height, radius: radius)
        }
    }

    public static func cone(height: Float, radius: Float) -> MeshResource {
        mesh(.init("cone", height, radius)) { .generateCone(height: height, radius: radius) }
    }

    /// A unit tube along Y, open at both ends, for a line that fades to
    /// nothing (`Materials.fadedLine`): its u runs from 1 at −Y to 0 at +Y,
    /// so stretched along a beam's direction it is whole where it leaves
    /// the beam and gone at its far end. `generateCylinder` gives no say
    /// over which way its texture runs.
    public static func fadeTube(sides: Int = 10) -> MeshResource {
        mesh(.init("fadeTube", Float(sides))) {
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var coordinates: [SIMD2<Float>] = []
            for ring in 0...1 {
                let y = Float(ring) - 0.5
                for side in 0...sides {
                    let angle = Float(side) / Float(sides) * 2 * .pi
                    let normal = SIMD3<Float>(cos(angle), 0, sin(angle))
                    positions.append(normal + SIMD3(0, y, 0))
                    normals.append(normal)
                    coordinates.append(SIMD2(0.5 - y, Float(side) / Float(sides)))
                }
            }
            let stride = UInt32(sides + 1)
            var indices: [UInt32] = []
            for side in 0..<UInt32(sides) {
                let a = side, b = side + 1, c = a + stride, d = b + stride
                // Wound to face outward.
                indices += [a, c, b, b, c, d]
            }
            var descriptor = MeshDescriptor(name: "fade-tube")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates)
            descriptor.primitives = .triangles(indices)
            return (try? MeshResource.generate(from: [descriptor]))
                ?? .generateCylinder(height: 1, radius: 1)
        }
    }

    // MARK: Colliders

    public static func collisionSphere(radius: Float,
                                       offset: SIMD3<Float> = .zero) -> ShapeResource {
        shape(.init("sphere", radius, offset.x, offset.y, offset.z)) {
            offset == .zero
                ? .generateSphere(radius: radius)
                : .generateSphere(radius: radius).offsetBy(translation: offset)
        }
    }

    public static func collisionBox(size: SIMD3<Float>,
                                    offset: SIMD3<Float> = .zero) -> ShapeResource {
        shape(.init("box", size.x, size.y, size.z, offset.x, offset.y, offset.z)) {
            offset == .zero
                ? .generateBox(size: size)
                : .generateBox(size: size).offsetBy(translation: offset)
        }
    }

    public static func collisionBox(width: Float, height: Float, depth: Float,
                                    offset: SIMD3<Float> = .zero) -> ShapeResource {
        collisionBox(size: [width, height, depth], offset: offset)
    }

    public static func collisionCapsule(height: Float, radius: Float,
                                        offset: SIMD3<Float> = .zero) -> ShapeResource {
        shape(.init("capsule", height, radius, offset.x, offset.y, offset.z)) {
            offset == .zero
                ? .generateCapsule(height: height, radius: radius)
                : .generateCapsule(height: height, radius: radius).offsetBy(translation: offset)
        }
    }

    // MARK: The caches

    /// Dimensions quantised to a micrometre: raw Float keys never match.
    struct Key: Hashable {
        let kind: String
        let values: [Int64]
        init(_ kind: String, _ values: Float...) {
            self.kind = kind
            self.values = values.map { Int64(($0 * 1_000_000).rounded()) }
        }
    }

    /// Bounded: a caller building continuously varying shapes (a cable
    /// of every length) must not grow the cache without limit. Clearing
    /// only stops sharing; entities keep the meshes they hold.
    static let capacity = 1_000

    private static var meshes: [Key: MeshResource] = [:]
    private static var shapes: [Key: ShapeResource] = [:]

    /// How many distinct meshes and colliders are held — for tests.
    public static var count: Int { meshes.count + shapes.count }

    private static func mesh(_ key: Key, _ make: () -> MeshResource) -> MeshResource {
        if let cached = meshes[key] { return cached }
        if meshes.count >= capacity { meshes.removeAll(keepingCapacity: true) }
        let made = make()
        meshes[key] = made
        return made
    }

    private static func shape(_ key: Key, _ make: () -> ShapeResource) -> ShapeResource {
        if let cached = shapes[key] { return cached }
        if shapes.count >= capacity { shapes.removeAll(keepingCapacity: true) }
        let made = make()
        shapes[key] = made
        return made
    }
}
