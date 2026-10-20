//
//  LiveTube.swift
//  RenderKit
//
//  Tubes that are re-meshed many times a second — field lines while a
//  charge or magnet is dragged, a projectile's arc while its bead is, an
//  orbit's prediction while a body is held — written into the entity's own
//  `LowLevelMesh` in place, instead of a `MeshResource` generated for every
//  update. Generating them was a quarter of Electric Fields' main thread
//  with its charges moving, and most of why its frames ran 17–22 ms. The
//  same exception to "the per-frame path touches only transforms" that
//  `TrailRibbons` and `SurfaceMesh` are.
//
//  THREE meshes, taken in turn. A `LowLevelMesh` write waits for the GPU
//  to let go of the buffer, and the frame just drawn still holds it: with
//  one mesh rewritten every frame, Electric Fields' main thread spent half
//  of every frame waiting on the renderer. Each write now goes into the
//  mesh drawn two frames ago, and the entity is handed that mesh.
//
//  The meshes live in a component on the entity, so nothing outlives it.
//  They are made once, with headroom, and remade only when a set of tubes
//  outgrows them. The material is set when they are made.
//

import Metal
import RealityKit
import simd

@MainActor
public enum LiveTube {
    private struct Store: Component {
        let meshes: [LowLevelMesh]
        let resources: [MeshResource]
        let vertexCapacity: Int
        let indexCapacity: Int
        /// The mesh the next write goes into.
        var next = 0
    }

    /// How many meshes take turns: one drawn, one in flight, one to write.
    static let rotation = 3

    private struct Vertex {
        var px: Float, py: Float, pz: Float
        var nx: Float, ny: Float, nz: Float
    }

    private static var registered = false

    /// Draws `buffers` on `entity`, rewriting its tube mesh in place.
    /// Empty buffers draw nothing (the model is cleared, the mesh kept).
    public static func apply(_ buffers: TubeBuffers, to entity: ModelEntity,
                             material: any RealityKit.Material) {
        if !registered {
            Store.registerComponent()
            registered = true
        }
        guard !buffers.isEmpty else {
            entity.model = nil
            return
        }
        var store = entity.components[Store.self]
        if let current = store,
           buffers.positions.count > current.vertexCapacity
            || buffers.indices.count > current.indexCapacity {
            store = nil
        }
        if store == nil {
            guard let made = make(vertices: grown(buffers.positions.count),
                                  indices: grown(buffers.indices.count)) else {
                // The GPU refused the buffers: draw the old way.
                entity.model = TubeMesh.mesh(from: buffers).map {
                    ModelComponent(mesh: $0, materials: [material])
                }
                return
            }
            store = made
        }
        guard var store else { return }
        let turn = store.next
        write(buffers, into: store.meshes[turn])
        if entity.model == nil {
            entity.model = ModelComponent(mesh: store.resources[turn], materials: [material])
        } else {
            entity.model?.mesh = store.resources[turn]
        }
        store.next = (turn + 1) % store.meshes.count
        entity.components.set(store)
    }

    /// Room to grow: half again, and never tiny.
    static func grown(_ count: Int) -> Int {
        max(1_024, Int((Double(count) * 1.5).rounded(.up)))
    }

    private static func make(vertices: Int, indices: Int) -> Store? {
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = vertices
        descriptor.indexCapacity = indices
        descriptor.indexType = .uint32
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
            .init(semantic: .normal, format: .float3, layoutIndex: 0,
                  offset: MemoryLayout<Float>.stride * 3),
        ]
        descriptor.vertexLayouts = [
            .init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride),
        ]
        var meshes: [LowLevelMesh] = []
        var resources: [MeshResource] = []
        for _ in 0..<rotation {
            guard let mesh = try? LowLevelMesh(descriptor: descriptor),
                  let resource = try? MeshResource(from: mesh) else { return nil }
            meshes.append(mesh)
            resources.append(resource)
        }
        return Store(meshes: meshes, resources: resources,
                     vertexCapacity: vertices, indexCapacity: indices)
    }

    private static func write(_ buffers: TubeBuffers, into mesh: LowLevelMesh) {
        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let count = buffers.positions.count
        let hasNormals = buffers.normals.count >= count
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Vertex.self)
            buffers.positions.withUnsafeBufferPointer { positions in
                buffers.normals.withUnsafeBufferPointer { normals in
                    for index in 0..<count {
                        let p = positions[index]
                        let n = hasNormals ? normals[index] : SIMD3<Float>(0, 1, 0)
                        vertices[index] = Vertex(px: p.x, py: p.y, pz: p.z,
                                                 nx: n.x, ny: n.y, nz: n.z)
                        lower = simd_min(lower, p)
                        upper = simd_max(upper, p)
                    }
                }
            }
        }
        // The indices are already the buffer's own type: one copy.
        mesh.withUnsafeMutableIndices { raw in
            buffers.indices.withUnsafeBytes { source in
                raw.copyMemory(from: source)
            }
        }
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexCount: buffers.indices.count, topology: .triangle,
                              bounds: BoundingBox(min: lower, max: upper)),
        ])
    }
}
