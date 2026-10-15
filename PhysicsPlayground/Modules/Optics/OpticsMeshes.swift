//
//  OpticsMeshes.swift
//  Physics Playground — Light & Optics
//
//  The optics as meshes, built from the same constants the tracer uses,
//  so what the light meets is exactly what the wearer sees: the prism's
//  faces are its half-spaces, the lens's faces its spheres. Procedural
//  rather than milled for that reason — a prop scaled to fit is a prop a
//  few millimetres off the physics.
//
//  Each mesh is built once and shared.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import UIKit
import simd

@MainActor
enum OpticsMeshes {

    // MARK: The prism

    /// The prism in its tracer frame: cross-section in xy (apex +y), height
    /// along z; flat faces, so each has its own vertices and normal.
    static let prism: MeshResource = {
        let corners = OpticalElement.prismCorners(apexAngle: OpticsModel.prismApex,
                                                  side: OpticsModel.prismSide)
            .map { SIMD2<Float>($0) }
        let h = Float(OpticsModel.prismHeight) / 2
        var builder = Builder()
        // The two end caps.
        builder.triangle(SIMD3(corners[0], h), SIMD3(corners[1], h), SIMD3(corners[2], h),
                         normal: [0, 0, 1])
        builder.triangle(SIMD3(corners[0], -h), SIMD3(corners[2], -h), SIMD3(corners[1], -h),
                         normal: [0, 0, -1])
        // The three long faces, outward.
        for index in 0..<3 {
            let a = corners[index], b = corners[(index + 1) % 3]
            let edge = b - a
            let normal = simd_normalize(SIMD3<Float>(edge.y, -edge.x, 0))
            builder.quad(SIMD3(a, -h), SIMD3(b, -h), SIMD3(b, h), SIMD3(a, h), normal: normal)
        }
        return builder.mesh(name: "optics-prism")
    }()

    // MARK: The lens

    /// The biconvex lens on its z-axis: two spherical caps and the thin
    /// cylindrical edge between them, smooth across each face and sharp at
    /// the rim.
    static let lens: MeshResource = {
        let radius = OpticsModel.lensRadius
        let half = OpticsModel.lensThickness / 2
        let aperture = OpticsModel.lensDiameter / 2
        let rings = 14, segments = 56
        var builder = Builder()

        func cap(front: Bool) {
            // Centre of curvature: behind the vertex by R.
            let centre = SIMD3<Double>(0, 0, front ? -half + radius : half - radius)
            func point(_ rho: Double, _ phi: Double) -> SIMD3<Double> {
                let sag = radius - (radius * radius - rho * rho).squareRoot()
                let z = front ? -half + sag : half - sag
                return SIMD3(rho * cos(phi), rho * sin(phi), z)
            }
            func normal(_ p: SIMD3<Double>) -> SIMD3<Float> {
                SIMD3<Float>(simd_normalize(p - centre))
            }
            for i in 0..<rings {
                let r0 = aperture * Double(i) / Double(rings)
                let r1 = aperture * Double(i + 1) / Double(rings)
                for j in 0..<segments {
                    let p0 = 2 * Double.pi * Double(j) / Double(segments)
                    let p1 = 2 * Double.pi * Double(j + 1) / Double(segments)
                    let a = point(r0, p0), b = point(r1, p0)
                    let c = point(r1, p1), d = point(r0, p1)
                    if i == 0 {
                        builder.smoothTriangle(a, b, c, normals: (normal(a), normal(b), normal(c)))
                    } else {
                        builder.smoothTriangle(a, b, c, normals: (normal(a), normal(b), normal(c)))
                        builder.smoothTriangle(a, c, d, normals: (normal(a), normal(c), normal(d)))
                    }
                }
            }
        }
        cap(front: true)
        cap(front: false)

        // The edge: where the two caps meet the cylinder of the aperture.
        let sag = radius - (radius * radius - aperture * aperture).squareRoot()
        let zFront = -half + sag, zBack = half - sag
        for j in 0..<segments {
            let p0 = 2 * Double.pi * Double(j) / Double(segments)
            let p1 = 2 * Double.pi * Double(j + 1) / Double(segments)
            let a = SIMD3(aperture * cos(p0), aperture * sin(p0), zFront)
            let b = SIMD3(aperture * cos(p1), aperture * sin(p1), zFront)
            let c = SIMD3(aperture * cos(p1), aperture * sin(p1), zBack)
            let d = SIMD3(aperture * cos(p0), aperture * sin(p0), zBack)
            let n0 = SIMD3<Float>(Float(cos(p0)), Float(sin(p0)), 0)
            let n1 = SIMD3<Float>(Float(cos(p1)), Float(sin(p1)), 0)
            builder.smoothTriangle(a, b, c, normals: (n0, n1, n1))
            builder.smoothTriangle(a, c, d, normals: (n0, n1, n0))
        }
        return builder.mesh(name: "optics-lens")
    }()

    // MARK: Edges

    /// A glass piece's edges as polylines, for its hairlines; nil for a
    /// piece that has none (the mirror's rim is its backing).
    static func edges(_ kind: OpticsModel.Kind) -> [[SIMD3<Float>]]? {
        switch kind {
        case .mirror:
            return nil
        case .prism:
            let corners = OpticalElement.prismCorners(apexAngle: OpticsModel.prismApex,
                                                      side: OpticsModel.prismSide)
                .map { SIMD2<Float>($0) }
            let h = Float(OpticsModel.prismHeight) / 2
            let loop = corners + [corners[0]]
            return [loop.map { SIMD3($0, h) }, loop.map { SIMD3($0, -h) }]
                + corners.map { [SIMD3($0, -h), SIMD3($0, h)] }
        case .block:
            let e = SIMD3<Float>(OpticsModel.blockHalfExtents)
            func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x * e.x, y * e.y, z * e.z) }
            return [
                [p(-1, -1, -1), p(1, -1, -1), p(1, 1, -1), p(-1, 1, -1), p(-1, -1, -1)],
                [p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1), p(-1, -1, 1)],
                [p(-1, -1, -1), p(-1, -1, 1)], [p(1, -1, -1), p(1, -1, 1)],
                [p(1, 1, -1), p(1, 1, 1)], [p(-1, 1, -1), p(-1, 1, 1)],
            ]
        case .lens:
            let radius = OpticsModel.lensRadius
            let aperture = OpticsModel.lensDiameter / 2
            let sag = radius - (radius * radius - aperture * aperture).squareRoot()
            let z = Float(OpticsModel.lensThickness / 2 - sag)
            return [-z, z].map { depth in
                (0...64).map { step in
                    let angle = Float(step) / 64 * 2 * .pi
                    return SIMD3(Float(aperture) * cos(angle), Float(aperture) * sin(angle), depth)
                }
            }
        }
    }

    // MARK: A triangle soup, wound outward

    /// Collects triangles and winds each so its face agrees with the normal
    /// it was given: a winding slip shows as a missing face, which is
    /// exactly what a transparent piece of glass cannot hide.
    private struct Builder {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                               normal: SIMD3<Float>) {
            add(a, b, c, normals: (normal, normal, normal))
        }

        mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                           _ d: SIMD3<Float>, normal: SIMD3<Float>) {
            triangle(a, b, c, normal: normal)
            triangle(a, c, d, normal: normal)
        }

        mutating func smoothTriangle(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>,
                                     normals: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)) {
            add(SIMD3<Float>(a), SIMD3<Float>(b), SIMD3<Float>(c), normals: normals)
        }

        private mutating func add(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                                  normals n: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)) {
            let face = simd_cross(b - a, c - a)
            guard simd_length(face) > 1e-12 else { return }
            let base = UInt32(positions.count)
            let wanted = n.0 + n.1 + n.2
            if simd_dot(face, wanted) >= 0 {
                positions += [a, b, c]
                normals += [n.0, n.1, n.2]
            } else {
                positions += [a, c, b]
                normals += [n.0, n.2, n.1]
            }
            indices += [base, base + 1, base + 2]
        }

        func mesh(name: String) -> MeshResource {
            var descriptor = MeshDescriptor(name: name)
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(indices)
            // A procedural mesh of a few thousand triangles; if RealityKit
            // refuses it, a box stands in rather than nothing.
            return (try? MeshResource.generate(from: [descriptor]))
                ?? Primitives.box(size: [0.05, 0.05, 0.05])
        }
    }
}
