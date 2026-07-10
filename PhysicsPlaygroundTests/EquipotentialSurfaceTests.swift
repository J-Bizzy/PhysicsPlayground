//
//  EquipotentialSurfaceTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the marching-tetrahedra equipotential extractor. The strongest
//  check exploits the exact geometry: for a single point charge, V = level
//  is a perfect sphere of radius r = kq/level.
//

import XCTest
import simd
@testable import PhysicsPlayground

final class EquipotentialSurfaceTests: XCTestCase {

    /// For one charge, every generated vertex must sit at distance kq/V from
    /// it (within grid resolution).
    func testSingleChargeShellIsASphereOfRadiusKQOverV() {
        let charge = PointCharge(position: SIMD3(0.1, 1.2, -1.0), charge: 1e-6)
        let radius = 0.2
        let level = ElectricField.k * charge.charge / radius   // V at 0.2 m

        let triangles = EquipotentialSurface.triangles(
            level: level,
            charges: [charge],
            center: charge.position,
            extents: SIMD3(repeating: 0.9),
            resolution: 28
        )

        XCTAssertFalse(triangles.isEmpty)
        XCTAssertEqual(triangles.count % 3, 0, "output must be whole triangles")

        let cellSize = 0.9 / 28.0
        for vertex in triangles {
            XCTAssertEqual(simd_distance(vertex, charge.position), radius, accuracy: cellSize,
                           "every vertex must lie on the kq/V sphere")
        }
    }

    /// The shell must be a closed surface all around the charge: vertices in
    /// every octant relative to the center.
    func testShellSurroundsTheChargeCompletely() {
        let charge = PointCharge(position: .zero, charge: 1e-6)
        let level = ElectricField.k * charge.charge / 0.2
        let triangles = EquipotentialSurface.triangles(
            level: level, charges: [charge],
            center: .zero, extents: SIMD3(repeating: 0.9), resolution: 24
        )
        for sx in [-1.0, 1.0] {
            for sy in [-1.0, 1.0] {
                for sz in [-1.0, 1.0] {
                    XCTAssertTrue(
                        triangles.contains { $0.x * sx > 0 && $0.y * sy > 0 && $0.z * sz > 0 },
                        "octant (\(sx), \(sy), \(sz)) must contain shell vertices"
                    )
                }
            }
        }
    }

    /// A level higher than any potential in the box yields no surface.
    func testUnreachableLevelYieldsNoTriangles() {
        let charge = PointCharge(position: .zero, charge: 1e-6)
        // V > kq/0.01 only within 1 cm of the charge; sample cells are ~4 cm,
        // outside the lattice's reach.
        let level = ElectricField.k * charge.charge / 0.001
        let triangles = EquipotentialSurface.triangles(
            level: level, charges: [charge],
            center: .zero, extents: SIMD3(repeating: 0.9), resolution: 20
        )
        XCTAssertTrue(triangles.isEmpty)
    }

    /// Negative charges get negative-level shells, positive levels none.
    func testNegativeChargeHasNegativeShells() {
        let charge = PointCharge(position: .zero, charge: -1e-6)
        let negativeLevel = -ElectricField.k * 1e-6 / 0.2
        let negative = EquipotentialSurface.triangles(
            level: negativeLevel, charges: [charge],
            center: .zero, extents: SIMD3(repeating: 0.9), resolution: 24
        )
        let positive = EquipotentialSurface.triangles(
            level: -negativeLevel, charges: [charge],
            center: .zero, extents: SIMD3(repeating: 0.9), resolution: 24
        )
        XCTAssertFalse(negative.isEmpty)
        XCTAssertTrue(positive.isEmpty)
    }

    /// The outward normal is parallel to E (that's why field lines cross
    /// shells at right angles): E = −∇V, and the level-set normal is ∇V.
    func testOutwardNormalIsParallelToField() {
        let charge = PointCharge(position: .zero, charge: 1e-6)
        let point = SIMD3<Double>(0.15, 0.1, -0.05)
        let normal = EquipotentialSurface.outwardNormal(at: point, level: 100.0, charges: [charge])
        let fieldDirection = simd_normalize(ElectricField.vector(at: point, dueTo: [charge]))
        XCTAssertEqual(simd_dot(normal, fieldDirection), 1.0, accuracy: 1e-9)
    }

    /// Default level selection: positive-only scenes get only positive
    /// levels, mixed scenes get both families.
    func testDefaultLevelsMatchPolaritiesPresent() {
        let positiveOnly = [PointCharge(position: .zero, charge: 1e-6)]
        XCTAssertTrue(EquipotentialSurface.defaultLevels(for: positiveOnly).allSatisfy { $0 > 0 })

        let mixed = [
            PointCharge(position: .zero, charge: 1e-6),
            PointCharge(position: SIMD3(0.3, 0, 0), charge: -1e-6),
        ]
        let levels = EquipotentialSurface.defaultLevels(for: mixed)
        XCTAssertTrue(levels.contains { $0 > 0 })
        XCTAssertTrue(levels.contains { $0 < 0 })
        XCTAssertTrue(EquipotentialSurface.defaultLevels(for: []).isEmpty)
    }
}
