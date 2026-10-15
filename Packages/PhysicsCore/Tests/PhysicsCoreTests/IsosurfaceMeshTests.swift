//
//  IsosurfaceMeshTests.swift
//  PhysicsCoreTests
//
//  The welded, many-level isosurfaces behind Electric Fields' equipotential
//  shells, against what an equipotential of a point charge must be: a
//  sphere of radius kq/V, closed (every edge shared by exactly two faces,
//  Euler characteristic 2), its normals radial and facing out of the
//  charge for either sign, and the triangle budget spent innermost first.
//  Round a dipole, where no closed form says where a shell lies, its faces
//  must still cross the field at right angles.
//

import XCTest
import simd
@testable import PhysicsCore

final class IsosurfaceMeshTests: XCTestCase {

    private let charge = PointCharge(position: SIMD3(0.1, 1.2, -0.3), charge: 1e-6)
    private var box: (center: SIMD3<Double>, extents: SIMD3<Double>) {
        (charge.position + SIMD3(0.013, -0.007, 0.011), SIMD3(repeating: 1.2))
    }

    private func shells(_ charges: [PointCharge], levels: [Double], resolution: Int = 40,
                        maxTriangles: Int = .max) -> [Isosurface.Mesh] {
        Isosurface.meshes(
            levels: levels,
            scalar: { ElectricField.potential(at: $0, dueTo: charges) },
            gradient: { -ElectricField.vector(at: $0, dueTo: charges) },
            center: box.center, extents: box.extents,
            resolution: resolution, maxTriangles: maxTriangles)
    }

    /// Every vertex lies at r = kq/V — to the Float it is stored in, not to
    /// a grid cell, because each is refined onto the exact surface — and its
    /// normal points straight out of the charge.
    func testAPointChargesEquipotentialIsTheSphereKqOverV() throws {
        let levels = [20_000.0, 40_000, 80_000]
        for mesh in shells([charge], levels: levels) {
            let radius = ElectricField.k * charge.charge / mesh.level
            for (position, normal) in zip(mesh.positions, mesh.normals) {
                let r = SIMD3<Double>(position) - charge.position
                XCTAssertEqual(simd_length(r), radius, accuracy: 1e-6)
                XCTAssertGreaterThan(simd_dot(SIMD3<Double>(normal), simd_normalize(r)), 0.99)
            }
        }
    }

    /// A negative charge's shells face out of it too: the normal follows
    /// the sign of the level, not the raw gradient.
    func testANegativeChargesShellsFaceOutOfItToo() throws {
        let negative = PointCharge(position: charge.position, charge: -1e-6)
        let mesh = try XCTUnwrap(shells([negative], levels: [-40_000]).first)
        for (position, normal) in zip(mesh.positions, mesh.normals) {
            let r = simd_normalize(SIMD3<Double>(position) - negative.position)
            XCTAssertGreaterThan(simd_dot(SIMD3<Double>(normal), r), 0.99)
        }
    }

    /// Without refinement a vertex is only where a linear f would cross
    /// the level: off the sphere by a visible fraction of a cell.
    func testRefinementIsWhatPutsTheVerticesOnTheSurface() throws {
        let charges = [charge]
        let coarse = try XCTUnwrap(Isosurface.meshes(
            levels: [80_000],
            scalar: { ElectricField.potential(at: $0, dueTo: charges) },
            gradient: { -ElectricField.vector(at: $0, dueTo: charges) },
            center: box.center, extents: box.extents, resolution: 40, refinement: 0).first)
        let radius = ElectricField.k * charge.charge / 80_000
        let worst = coarse.positions.map { abs(simd_length(SIMD3<Double>($0) - charge.position) - radius) }.max() ?? 0
        XCTAssertGreaterThan(worst, 1e-3, "the linear crossing should be visibly off a 11 cm sphere")
    }

    /// Closed and of a sphere's topology: each edge in exactly two faces,
    /// and V − E + F = 2 — no holes, no cracks between cells.
    func testEachShellIsClosed() throws {
        let mesh = try XCTUnwrap(shells([charge], levels: [30_000]).first)
        XCTAssertTrue(mesh.isClosed)
        var edges: [UInt64: Int] = [:]
        for t in Swift.stride(from: 0, to: mesh.indices.count, by: 3) {
            let tri = [mesh.indices[t], mesh.indices[t + 1], mesh.indices[t + 2]]
            for (a, b) in [(tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])] {
                let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                edges[key, default: 0] += 1
            }
        }
        XCTAssertTrue(edges.values.allSatisfy { $0 == 2 }, "a shell has a crack or a fold")
        let euler = mesh.positions.count - edges.count + mesh.triangleCount
        XCTAssertEqual(euler, 2)
    }

    /// One sampling serves every level: each surface matches what it would
    /// be meshed alone.
    func testManyLevelsMatchOneAtATime() {
        let charges = [charge, PointCharge(position: charge.position + SIMD3(0.3, 0, 0), charge: -1e-6)]
        let together = shells(charges, levels: [-60_000, -20_000, 20_000, 60_000])
        for mesh in together {
            let alone = shells(charges, levels: [mesh.level])
            XCTAssertEqual(alone.first?.triangleCount, mesh.triangleCount)
        }
    }

    /// The field crosses every equipotential at right angles. The faces'
    /// own normals are measured from the triangles, not taken from the
    /// gradient the vertex normals were built from, so this checks where
    /// the surface lies, round a dipole as well as a lone charge.
    func testTheShellsCrossTheFieldAtRightAngles() {
        let charges = [charge, PointCharge(position: charge.position + SIMD3(0.4, 0, 0), charge: -1e-6)]
        let meshes = shells(charges, levels: [-40_000, -20_000, 0, 20_000, 40_000], resolution: 60)
        XCTAssertEqual(meshes.count, 5)
        for mesh in meshes {
            var alignment = 0.0, area = 0.0
            for t in Swift.stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = SIMD3<Double>(mesh.positions[Int(mesh.indices[t])])
                let b = SIMD3<Double>(mesh.positions[Int(mesh.indices[t + 1])])
                let c = SIMD3<Double>(mesh.positions[Int(mesh.indices[t + 2])])
                let cross = simd_cross(b - a, c - a)
                let faceArea = simd_length(cross) / 2
                guard faceArea > 0 else { continue }
                let field = ElectricField.vector(at: (a + b + c) / 3, dueTo: charges)
                alignment += faceArea * abs(simd_dot(simd_normalize(cross), simd_normalize(field)))
                area += faceArea
            }
            // Area-weighted mean |cos|: 1 is the field exactly along every
            // face's normal. A cell's worth of facet error costs a little.
            XCTAssertGreaterThan(alignment / area, 0.99, "level \(mesh.level)")
        }
    }

    /// Equal and opposite charges: their 0 V surface is the infinite plane
    /// between them, which the box cuts, and the mesh knows it is open.
    func testTheBoxCutsTheBalancedDipolesZeroSurface() throws {
        let charges = [charge, PointCharge(position: charge.position + SIMD3(0.4, 0, 0), charge: -1e-6)]
        let meshes = shells(charges, levels: [0, 40_000])
        let zero = try XCTUnwrap(meshes.first { $0.level == 0 })
        XCTAssertFalse(zero.isClosed)
        XCTAssertTrue(try XCTUnwrap(meshes.first { $0.level == 40_000 }).isClosed)
    }

    /// Over budget, the outermost (largest) shells go first, and the budget
    /// holds.
    func testTheBudgetDropsTheOutermostShellsFirst() {
        let levels = [15_000.0, 30_000, 60_000, 120_000]
        let all = shells([charge], levels: levels)
        let budget = all.filter { $0.level >= 60_000 }.map(\.triangleCount).reduce(0, +)
        let kept = shells([charge], levels: levels, maxTriangles: budget)
        XCTAssertLessThanOrEqual(kept.map(\.triangleCount).reduce(0, +), budget)
        XCTAssertEqual(Set(kept.map(\.level)), [60_000, 120_000])
    }
}
