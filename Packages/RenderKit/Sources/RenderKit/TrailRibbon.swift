//
//  TrailRibbon.swift
//  RenderKit
//
//  A bounded polyline tube whose vertices are rewritten in place: RealityKit's
//  `LowLevelMesh`, so a trail that grows and fades with its body costs a buffer
//  write per frame, never a `MeshResource` regeneration. The documented
//  exception to "the per-frame path touches only transforms" (ARCHITECTURE.md):
//  a ring buffer updated in place is not regeneration.
//
//  Vertex buffer 0 carries position and normal; buffer 1 carries uv0, whose u
//  is the point's age (0 at the tail, 1 at the body) — a material with an
//  opacity ramp along u fades the tail to nothing.
//

import Metal
import RealityKit
import simd

@MainActor
public final class TrailRibbon {
    public let entity = ModelEntity()
    public let capacity: Int
    public let sides: Int

    private struct Vertex {
        var px: Float, py: Float, pz: Float
        var nx: Float, ny: Float, nz: Float
    }
    private struct Fade {
        var u: Float, v: Float
    }

    private let mesh: LowLevelMesh
    private var ringCount = 0
    private var bounds = BoundingBox()

    /// Fails only if the GPU refuses the buffers; a caller then draws nothing.
    public init?(capacity: Int, sides: Int = 5) {
        self.capacity = max(capacity, 2)
        self.sides = max(sides, 3)
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = self.capacity * self.sides
        descriptor.indexCapacity = (self.capacity - 1) * self.sides * 6
        descriptor.indexType = .uint32
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
            .init(semantic: .normal, format: .float3, layoutIndex: 0,
                  offset: MemoryLayout<Float>.stride * 3),
            .init(semantic: .uv0, format: .float2, layoutIndex: 1, offset: 0),
        ]
        descriptor.vertexLayouts = [
            .init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride),
            .init(bufferIndex: 1, bufferStride: MemoryLayout<Fade>.stride),
        ]
        guard let mesh = try? LowLevelMesh(descriptor: descriptor),
              let resource = try? MeshResource(from: mesh) else { return nil }
        self.mesh = mesh
        entity.model = ModelComponent(mesh: resource, materials: [UnlitMaterial(color: .white)])
        entity.isEnabled = false
    }

    public func setMaterial(_ material: RealityKit.Material) {
        entity.model?.materials = [material]
    }

    /// The ring frame at `index` along `points` — the same central-difference
    /// rule `TubeMesh` uses, so a ribbon and a tube of one path agree.
    private static func frame(_ points: [SIMD3<Float>], _ index: Int)
        -> (side: SIMD3<Float>, up: SIMD3<Float>)? {
        let prev = points[max(index - 1, 0)]
        let next = points[min(index + 1, points.count - 1)]
        var tangent = next - prev
        let length = simd_length(tangent)
        guard length > 1e-7 else { return nil }
        tangent /= length
        let reference: SIMD3<Float> = abs(tangent.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let side = simd_normalize(simd_cross(tangent, reference))
        return (side, simd_cross(tangent, side))
    }

    /// Rewrites the whole tube for `points` (tail first, head last), each with
    /// an age in 0…1, at `radius`. Fewer than two distinct points empties it.
    public func update(points: [SIMD3<Float>], ages: [Float], radius: Float) {
        let count = min(points.count, capacity)
        let path = Array(points.suffix(count))
        let agePath = Array(ages.suffix(count))
        guard count >= 2 else {
            clear()
            return
        }
        var rings = 0
        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Vertex.self)
            for index in 0..<count {
                guard let (side, up) = Self.frame(path, index) else { continue }
                let point = path[index]
                for s in 0..<sides {
                    let angle = 2 * Float.pi * Float(s) / Float(sides)
                    let direction = cos(angle) * side + sin(angle) * up
                    let position = point + radius * direction
                    vertices[rings * sides + s] = Vertex(
                        px: position.x, py: position.y, pz: position.z,
                        nx: direction.x, ny: direction.y, nz: direction.z)
                    lower = simd_min(lower, position)
                    upper = simd_max(upper, position)
                }
                rings += 1
            }
        }
        guard rings >= 2 else {
            clear()
            return
        }
        ringCount = rings
        writeAges(agePath)
        let indexCount = (rings - 1) * sides * 6
        mesh.withUnsafeMutableIndices { raw in
            let indices = raw.bindMemory(to: UInt32.self)
            var cursor = 0
            for ring in 0..<(rings - 1) {
                let a = UInt32(ring * sides)
                let b = a + UInt32(sides)
                for s in 0..<UInt32(sides) {
                    let next = (s + 1) % UInt32(sides)
                    indices[cursor] = a + s; indices[cursor + 1] = b + s; indices[cursor + 2] = a + next
                    indices[cursor + 3] = a + next; indices[cursor + 4] = b + s; indices[cursor + 5] = b + next
                    cursor += 6
                }
            }
        }
        bounds = BoundingBox(min: lower, max: upper)
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexOffset: 0, indexCount: indexCount, topology: .triangle,
                              materialIndex: 0, bounds: bounds),
        ])
        entity.isEnabled = true
    }

    /// Moves the head ring, and re-aims the ring before it, for a path whose
    /// samples are unchanged and whose last point is the body's new position
    /// — the running frame's whole cost. Falls back to a full rewrite when
    /// the ring count no longer matches.
    public func updateHead(points: [SIMD3<Float>], ages: [Float], radius: Float) {
        let count = min(points.count, capacity)
        guard count >= 2, count == ringCount else {
            update(points: points, ages: ages, radius: radius)
            return
        }
        let path = Array(points.suffix(count))
        var lower = bounds.min, upper = bounds.max
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Vertex.self)
            for index in [count - 2, count - 1] {
                guard let (side, up) = Self.frame(path, index) else { continue }
                let point = path[index]
                for s in 0..<sides {
                    let angle = 2 * Float.pi * Float(s) / Float(sides)
                    let direction = cos(angle) * side + sin(angle) * up
                    let position = point + radius * direction
                    vertices[index * sides + s] = Vertex(
                        px: position.x, py: position.y, pz: position.z,
                        nx: direction.x, ny: direction.y, nz: direction.z)
                    lower = simd_min(lower, position)
                    upper = simd_max(upper, position)
                }
            }
        }
        bounds = BoundingBox(min: lower, max: upper)
        writeAges(Array(ages.suffix(count)))
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexOffset: 0, indexCount: (count - 1) * sides * 6,
                              topology: .triangle, materialIndex: 0, bounds: bounds),
        ])
    }

    /// Rewrites only the fade — the ages move every frame while the shape
    /// changes only when a sample is added or dropped.
    public func updateAges(_ ages: [Float]) {
        guard ringCount >= 2 else { return }
        writeAges(Array(ages.suffix(ringCount)))
    }

    private func writeAges(_ ages: [Float]) {
        mesh.withUnsafeMutableBytes(bufferIndex: 1) { raw in
            let fades = raw.bindMemory(to: Fade.self)
            for ring in 0..<ringCount {
                let age = ring < ages.count ? ages[ring] : 1
                for s in 0..<sides {
                    fades[ring * sides + s] = Fade(u: age, v: Float(s) / Float(sides))
                }
            }
        }
    }

    public func clear() {
        guard ringCount != 0 || entity.isEnabled else { return }
        ringCount = 0
        mesh.parts.removeAll()
        entity.isEnabled = false
    }

    public var isEmpty: Bool { ringCount == 0 }
}
