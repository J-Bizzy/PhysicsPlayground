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
