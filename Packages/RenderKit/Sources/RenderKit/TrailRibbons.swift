//
//  TrailRibbons.swift
//  RenderKit
//
//  Bounded polyline tubes — one per slot, each a part of ONE `LowLevelMesh`
//  with its own material — whose vertices are rewritten in place: a trail
//  that grows and fades with its body costs a buffer write per frame, never
//  a `MeshResource` regeneration. The documented exception to "the per-frame
//  path touches only transforms" (ARCHITECTURE.md): a buffer updated in place
//  is not regeneration.
//
//  ONE MESH, NOT ONE PER TRAIL. Every write to a `LowLevelMesh` buffer hands
//  the renderer — another process on visionOS — a new payload, and the main
//  thread waits whenever the renderer has not yet let go of the last ones.
//  Orbital Mechanics' ten trails as ten meshes made twenty payloads a frame,
//  and the simulator's main thread spent 58 % of its time in
//  `__REALITYKIT_WAITING_ON_RENDERER__` and none idle. So a frame's changes
//  are staged per slot and `commit()` writes each buffer once.
//
//  ROTATION, for trails that are wholly rewritten every frame (the opening's
//  worlds, 2026-10-20): even one mesh written every frame left the main
//  thread waiting on the renderer for half of it, because the frame just
//  drawn still holds the buffers. With `rotation` 3 each commit writes every
//  live trail into the next of three meshes and hands the entity that one.
//  Head-only updates become full rewrites there; Orbital Mechanics, whose
//  trails mostly move only their heads and commit at most 30 times a
//  second, keeps one mesh.
//
//  Vertex buffer 0 carries position and normal; buffer 1 carries uv0, whose u
//  is the point's age (0 at the tail, 1 at the body) — a material with an
//  opacity ramp along u fades the tail to nothing.
//

import Metal
import RealityKit
import simd

@MainActor
public final class TrailRibbons {
    public let entity = ModelEntity()
    public let slots: Int
    /// Rings per slot: the most samples one trail can draw.
    public let capacity: Int
    public let sides: Int

    private struct Vertex {
        var px: Float, py: Float, pz: Float
        var nx: Float, ny: Float, nz: Float
    }
    private struct Fade {
        var u: Float, v: Float
    }

    private enum Pending {
        case full(points: [SIMD3<Float>], ages: [Float], radius: Float)
        case head(points: [SIMD3<Float>], ages: [Float], radius: Float)
        case clear
    }

    private let meshes: [LowLevelMesh]
    private let resources: [MeshResource]
    /// The mesh the next commit writes; with one mesh, always that one.
    private var current = 0
    private var mesh: LowLevelMesh { meshes[current] }
    /// Every live slot's last full path, for a rotating ribbon's rewrite.
    private var lastFull: [Int: (points: [SIMD3<Float>], ages: [Float], radius: Float)] = [:]
    /// What each mesh's fade and index buffers already hold, per slot: a
    /// buffer is written only where it would change. Every write is a
    /// payload the renderer must take, and it takes only so many a frame —
    /// the opening's trails, rewriting all three buffers every frame, left
    /// the main thread waiting on it most of the time, though only their
    /// positions ever changed.
    private var writtenRings: [[Int]]
    private var writtenAges: [[[Float]]]
    private var ringCounts: [Int]
    private var bounds: [BoundingBox]
    private var pending: [Int: Pending] = [:]
    private var materials: [RealityKit.Material]

    private var verticesPerSlot: Int { capacity * sides }
    private var indicesPerSlot: Int { (capacity - 1) * sides * 6 }

    /// Fails only if the GPU refuses the buffers; a caller then draws nothing.
    /// - rotation: how many meshes take turns; more than 1 rewrites every
    ///   live trail on every commit, and never waits on the renderer.
    public init?(slots: Int, capacity: Int, sides: Int = 5, rotation: Int = 1) {
        self.slots = max(slots, 1)
        self.capacity = max(capacity, 2)
        self.sides = max(sides, 3)
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = self.slots * self.capacity * self.sides
        descriptor.indexCapacity = self.slots * (self.capacity - 1) * self.sides * 6
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
        var meshes: [LowLevelMesh] = []
        var resources: [MeshResource] = []
        for _ in 0..<max(rotation, 1) {
            guard let mesh = try? LowLevelMesh(descriptor: descriptor),
                  let resource = try? MeshResource(from: mesh) else { return nil }
            meshes.append(mesh)
            resources.append(resource)
        }
        self.meshes = meshes
        self.resources = resources
        ringCounts = Array(repeating: 0, count: self.slots)
        writtenRings = Array(repeating: Array(repeating: 0, count: self.slots), count: meshes.count)
        writtenAges = Array(repeating: Array(repeating: [], count: self.slots), count: meshes.count)
        bounds = Array(repeating: BoundingBox(), count: self.slots)
        materials = Array(repeating: UnlitMaterial(color: .white), count: self.slots)
        entity.model = ModelComponent(mesh: resources[0], materials: materials)
        entity.isEnabled = false
    }

    /// What one slot's tube wears; the others keep theirs.
    public func setMaterial(_ material: RealityKit.Material, slot: Int) {
        guard materials.indices.contains(slot) else { return }
        materials[slot] = material
        entity.model?.materials = materials
    }

    public func isEmpty(slot: Int) -> Bool {
        guard ringCounts.indices.contains(slot) else { return true }
        switch pending[slot] {
        case .clear: return true
        case .full(let points, _, _): return min(points.count, capacity) < 2
        default: return ringCounts[slot] == 0
        }
    }

    /// How many slots draw a tube (as of the last commit, with what is staged).
    public var liveCount: Int { (0..<slots).filter { !isEmpty(slot: $0) }.count }

    /// Stages a rewrite of one slot's whole tube for `points` (tail first,
    /// head last), each with an age in 0…1, at `radius`. Fewer than two
    /// distinct points empties it.
    public func update(slot: Int, points: [SIMD3<Float>], ages: [Float], radius: Float) {
        guard ringCounts.indices.contains(slot) else { return }
        pending[slot] = .full(points: points, ages: ages, radius: radius)
    }

    /// Stages a move of the head ring, and a re-aim of the ring before it,
    /// for a path whose samples are unchanged and whose last point is the
    /// body's new position — the running frame's whole cost. Becomes a full
    /// rewrite when the ring count no longer matches.
    public func updateHead(slot: Int, points: [SIMD3<Float>], ages: [Float], radius: Float) {
        guard ringCounts.indices.contains(slot) else { return }
        if case .full = pending[slot] {
            pending[slot] = .full(points: points, ages: ages, radius: radius)
        } else {
            pending[slot] = .head(points: points, ages: ages, radius: radius)
        }
    }

    public func clear(slot: Int) {
        guard ringCounts.indices.contains(slot) else { return }
        if ringCounts[slot] == 0, pending[slot] == nil { return }
        pending[slot] = .clear
    }

    /// Writes everything staged since the last commit: the vertex buffer,
    /// the fade buffer and the index buffer once each, at most.
    public func commit() {
        guard !pending.isEmpty else { return }
        var staged = pending
        pending.removeAll()

        // Rotating: the next mesh holds nothing current, so every live slot
        // is written whole into it.
        if meshes.count > 1 {
            for (slot, work) in staged {
                switch work {
                case .clear: lastFull[slot] = nil
                case .full(let points, let ages, let radius), .head(let points, let ages, let radius):
                    lastFull[slot] = (points, ages, radius)
                }
            }
            staged = [:]
            for slot in 0..<slots {
                if let path = lastFull[slot] {
                    staged[slot] = .full(points: path.points, ages: path.ages, radius: path.radius)
                } else {
                    staged[slot] = .clear
                }
            }
            current = (current + 1) % meshes.count
        }

        // Resolve each slot's work: a head move on a slot whose ring count
        // has changed is a full rewrite.
        var fulls: [(slot: Int, path: [SIMD3<Float>], ages: [Float], radius: Float)] = []
        var heads: [(slot: Int, path: [SIMD3<Float>], ages: [Float], radius: Float)] = []
        for (slot, work) in staged {
            switch work {
            case .clear:
                ringCounts[slot] = 0
            case .full(let points, let ages, let radius):
                let count = min(points.count, capacity)
                if count < 2 {
                    ringCounts[slot] = 0
                } else {
                    fulls.append((slot, Array(points.suffix(count)), Array(ages.suffix(count)), radius))
                }
            case .head(let points, let ages, let radius):
                let count = min(points.count, capacity)
                if count >= 2, count == ringCounts[slot] {
                    heads.append((slot, Array(points.suffix(count)), Array(ages.suffix(count)), radius))
                } else if count < 2 {
                    ringCounts[slot] = 0
                } else {
                    fulls.append((slot, Array(points.suffix(count)), Array(ages.suffix(count)), radius))
                }
            }
        }

        if !fulls.isEmpty || !heads.isEmpty {
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                let vertices = raw.bindMemory(to: Vertex.self)
                for work in fulls {
                    let base = work.slot * verticesPerSlot
                    var rings = 0
                    var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
                    var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
                    for index in work.path.indices {
                        guard let frame = Self.frame(work.path, index) else { continue }
                        writeRing(vertices, at: base + rings * sides, point: work.path[index],
                                  frame: frame, radius: work.radius, lower: &lower, upper: &upper)
                        rings += 1
                    }
                    ringCounts[work.slot] = rings >= 2 ? rings : 0
                    bounds[work.slot] = BoundingBox(min: lower, max: upper)
                }
                for work in heads {
                    let base = work.slot * verticesPerSlot
                    var lower = bounds[work.slot].min, upper = bounds[work.slot].max
                    for index in [work.path.count - 2, work.path.count - 1] {
                        guard let frame = Self.frame(work.path, index) else { continue }
                        writeRing(vertices, at: base + index * sides, point: work.path[index],
                                  frame: frame, radius: work.radius, lower: &lower, upper: &upper)
                    }
                    bounds[work.slot] = BoundingBox(min: lower, max: upper)
                }
            }
            // Ages only where they differ from what this mesh holds.
            let refaded = (fulls + heads).filter { work in
                ringCounts[work.slot] >= 2
                    && (writtenRings[current][work.slot] != ringCounts[work.slot]
                        || writtenAges[current][work.slot] != Array(work.ages.prefix(ringCounts[work.slot])))
            }
            if !refaded.isEmpty {
                mesh.withUnsafeMutableBytes(bufferIndex: 1) { raw in
                    let fades = raw.bindMemory(to: Fade.self)
                    for work in refaded {
                        let base = work.slot * verticesPerSlot
                        for ring in 0..<ringCounts[work.slot] {
                            let age = ring < work.ages.count ? work.ages[ring] : 1
                            for s in 0..<sides {
                                fades[base + ring * sides + s] = Fade(u: age, v: Float(s) / Float(sides))
                            }
                        }
                        writtenAges[current][work.slot] = Array(work.ages.prefix(ringCounts[work.slot]))
                    }
                }
            }
        }
        // Indices only where this mesh's ring count for the slot changed.
        let rewired = fulls.filter {
            ringCounts[$0.slot] >= 2 && writtenRings[current][$0.slot] != ringCounts[$0.slot]
        }
        if !rewired.isEmpty {
            mesh.withUnsafeMutableIndices { raw in
                let indices = raw.bindMemory(to: UInt32.self)
                for work in rewired {
                    var cursor = work.slot * indicesPerSlot
                    let vertexBase = UInt32(work.slot * verticesPerSlot)
                    writtenRings[current][work.slot] = ringCounts[work.slot]
                    for ring in 0..<(ringCounts[work.slot] - 1) {
                        let a = vertexBase + UInt32(ring * sides)
                        let b = a + UInt32(sides)
                        for s in 0..<UInt32(sides) {
                            let next = (s + 1) % UInt32(sides)
                            indices[cursor] = a + s; indices[cursor + 1] = b + s
                            indices[cursor + 2] = a + next
                            indices[cursor + 3] = a + next; indices[cursor + 4] = b + s
                            indices[cursor + 5] = b + next
                            cursor += 6
                        }
                    }
                }
            }
        }

        var parts: [LowLevelMesh.Part] = []
        for slot in 0..<slots where ringCounts[slot] >= 2 {
            parts.append(LowLevelMesh.Part(
                indexOffset: slot * indicesPerSlot * MemoryLayout<UInt32>.stride,
                indexCount: (ringCounts[slot] - 1) * sides * 6, topology: .triangle,
                materialIndex: slot, bounds: bounds[slot]))
        }
        mesh.parts.replaceAll(parts)
        if meshes.count > 1 { entity.model?.mesh = resources[current] }
        entity.isEnabled = !parts.isEmpty
    }

    private func writeRing(_ vertices: UnsafeMutableBufferPointer<Vertex>, at offset: Int,
                           point: SIMD3<Float>, frame: (side: SIMD3<Float>, up: SIMD3<Float>),
                           radius: Float, lower: inout SIMD3<Float>, upper: inout SIMD3<Float>) {
        for s in 0..<sides {
            let angle = 2 * Float.pi * Float(s) / Float(sides)
            let direction = cos(angle) * frame.side + sin(angle) * frame.up
            let position = point + radius * direction
            vertices[offset + s] = Vertex(px: position.x, py: position.y, pz: position.z,
                                          nx: direction.x, ny: direction.y, nz: direction.z)
            lower = simd_min(lower, position)
            upper = simd_max(upper, position)
        }
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
}
