//
//  SurfaceMesh.swift
//  RenderKit
//
//  Several indexed surfaces in one `LowLevelMesh`, rewritten in place: each
//  surface a part with its own material index, so a set of surfaces that is
//  re-meshed many times a second (Electric Fields' equipotential shells,
//  while a charge is dragged) costs a buffer write on the main thread, never
//  a `MeshResource` regeneration per surface. The same exception to "the
//  per-frame path touches only transforms" that `TrailRibbons` is: a buffer
//  updated in place is not regeneration.
//
//  Capacity is fixed when it is made. A set larger than that keeps the
//  surfaces that fit, in the order given, and drops the rest whole — the
//  caller orders them by what matters most.
//

import Metal
import RealityKit
import simd

@MainActor
public final class SurfaceMesh {
    public let entity = ModelEntity()
    public let vertexCapacity: Int
    public let indexCapacity: Int

    /// One surface: its vertices, unit normals, triangle indices into its
    /// own vertices, and which of the entity's materials it wears.
    public struct Surface: Sendable {
        public var positions: [SIMD3<Float>]
        public var normals: [SIMD3<Float>]
        public var indices: [UInt32]
        public var material: Int

        public init(positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32],
                    material: Int) {
            self.positions = positions
            self.normals = normals
            self.indices = indices
            self.material = material
        }
    }

    private struct Vertex {
        var px: Float, py: Float, pz: Float
        var nx: Float, ny: Float, nz: Float
    }

    private let mesh: LowLevelMesh

    /// How many surfaces the last update drew.
    public private(set) var drawn = 0

    /// Fails only if the GPU refuses the buffers; a caller then draws nothing.
    public init?(vertexCapacity: Int, indexCapacity: Int, materials: [RealityKit.Material]) {
        self.vertexCapacity = max(vertexCapacity, 3)
        self.indexCapacity = max(indexCapacity, 3)
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = self.vertexCapacity
        descriptor.indexCapacity = self.indexCapacity
        descriptor.indexType = .uint32
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
            .init(semantic: .normal, format: .float3, layoutIndex: 0,
                  offset: MemoryLayout<Float>.stride * 3),
        ]
        descriptor.vertexLayouts = [
            .init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride),
        ]
        guard let mesh = try? LowLevelMesh(descriptor: descriptor),
              let resource = try? MeshResource(from: mesh) else { return nil }
        self.mesh = mesh
        entity.model = ModelComponent(mesh: resource, materials: materials)
        entity.isEnabled = false
    }

    /// Rewrites every surface. Those that would overflow the buffers, in
    /// the order given, are left out whole.
    public func update(_ surfaces: [Surface]) {
        var vertexBase = 0, indexBase = 0
        var kept: [(surface: Surface, vertexBase: Int, indexBase: Int)] = []
        for surface in surfaces where !surface.indices.isEmpty {
            guard vertexBase + surface.positions.count <= vertexCapacity,
                  indexBase + surface.indices.count <= indexCapacity else { break }
            kept.append((surface, vertexBase, indexBase))
            vertexBase += surface.positions.count
            indexBase += surface.indices.count
        }
        guard !kept.isEmpty else {
            clear()
            return
        }

        var parts: [LowLevelMesh.Part] = []
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Vertex.self)
            for entry in kept {
                var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
                var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
                for (offset, (p, n)) in zip(entry.surface.positions, entry.surface.normals).enumerated() {
                    vertices[entry.vertexBase + offset] = Vertex(px: p.x, py: p.y, pz: p.z,
                                                                 nx: n.x, ny: n.y, nz: n.z)
                    lower = simd_min(lower, p)
                    upper = simd_max(upper, p)
                }
                parts.append(LowLevelMesh.Part(
                    indexOffset: entry.indexBase * MemoryLayout<UInt32>.stride,
                    indexCount: entry.surface.indices.count, topology: .triangle,
                    materialIndex: entry.surface.material,
                    bounds: BoundingBox(min: lower, max: upper)))
            }
        }
        mesh.withUnsafeMutableIndices { raw in
            let indices = raw.bindMemory(to: UInt32.self)
            for entry in kept {
                let shift = UInt32(entry.vertexBase)
                for (offset, index) in entry.surface.indices.enumerated() {
                    indices[entry.indexBase + offset] = index + shift
                }
            }
        }
        mesh.parts.replaceAll(parts)
        drawn = kept.count
        entity.isEnabled = true
    }

    public func clear() {
        mesh.parts.removeAll()
        drawn = 0
        entity.isEnabled = false
    }
}
