//
//  IsosurfaceTests.swift
//  PhysicsCoreTests
//
//  Geometry recovery for marching tetrahedra. No stored triangle lists —
//  that would pin the implementation, not the mathematics.
//

import XCTest
import simd
@testable import PhysicsCore

final class IsosurfaceTests: XCTestCase {

    /// Sum of triangle areas — independent of how the surface is cut up.
    private func area(_ triangles: [SIMD3<Double>]) -> Double {
        var total = 0.0
        for base in stride(from: 0, to: triangles.count - 2, by: 3) {
            let a = triangles[base + 1] - triangles[base]
            let b = triangles[base + 2] - triangles[base]
            total += simd_length(simd_cross(a, b)) / 2
        }
        return total
    }

    /// A sphere: f(r) = |r| at level R.
    private func sphere(radius: Double, resolution: Int) -> [SIMD3<Double>] {
        Isosurface.triangles(
            level: radius,
            scalar: { simd_length($0) },
            outwardDirection: { $0 },
            center: .zero,
            extents: SIMD3(repeating: radius * 4),
            resolution: resolution)
    }

    /// 4πr² recovered. Tolerance 4% at resolution 32: an inscribed faceted
    /// mesh always under-reports — discretisation error, with a sign.
    func testASphereRecoversFourPiRSquared() {
        let radius = 1.0
        let measured = area(sphere(radius: radius, resolution: 32))
        let exact = 4 * Double.pi * radius * radius
        XCTAssertEqual(measured, exact, accuracy: exact * 0.04,
                       "Triangulated area \(measured) against 4πr² = \(exact).")
        XCTAssertLessThanOrEqual(measured, exact * 1.001,
                                 "A faceted mesh inscribed in a sphere cannot "
                                 + "have MORE area than the sphere.")
    }

    /// Refinement must move the answer toward the closed form — catches a
    /// constant offset the area test alone would tolerate.
    func testRefiningTheGridConvergesOnTheTrueArea() {
        let exact = 4 * Double.pi
        let coarse = abs(area(sphere(radius: 1, resolution: 12)) - exact)
        let fine = abs(area(sphere(radius: 1, resolution: 32)) - exact)
        XCTAssertLessThan(fine, coarse,
                          "Error grew from \(coarse) to \(fine) as the grid "
                          + "was refined — that is not convergence.")
    }

    /// Every vertex on the level set to within O(h²), not machine precision:
    /// chord interpolation lands systematically inside a convex level set.
    func testEveryVertexLiesOnTheLevelSetToWithinTheGridResolution() {
        let radius = 0.8
        let resolution = 16
        let cell = radius * 4 / Double(resolution)
        let tolerance = cell * cell            // O(h²), generously
        let triangles = sphere(radius: radius, resolution: resolution)
        XCTAssertFalse(triangles.isEmpty)

        var worst = 0.0
        for vertex in triangles {
            let distance = simd_length(vertex)
            worst = max(worst, abs(distance - radius))
            XCTAssertEqual(distance, radius, accuracy: tolerance,
                           "A vertex sits at |r| = \(distance), off the "
                           + "\(radius) level set by more than the grid can "
                           + "explain.")
            XCTAssertLessThanOrEqual(distance, radius + 1e-12,
                                     "Linear interpolation across a convex "
                                     + "level set lands inside it, never "
                                     + "outside.")
        }
        // Second order in practice: error well under the cell size.
        XCTAssertLessThan(worst, cell * 0.1,
                          "Worst vertex error \(worst) against cell \(cell).")
    }

    /// A plane: the field is linear, so interpolation is exact — a flat sheet
    /// at exactly x = 0.25 with the box's cross-section area.
    func testAPlaneIsRecoveredExactly() {
        let level = 0.25
        let triangles = Isosurface.triangles(
            level: level,
            scalar: { $0.x },
            outwardDirection: { _ in SIMD3(1, 0, 0) },
            center: .zero,
            extents: SIMD3(repeating: 2),
            resolution: 10)

        XCTAssertFalse(triangles.isEmpty, "The plane crosses the box.")
        for vertex in triangles {
            XCTAssertEqual(vertex.x, level, accuracy: 1e-12,
                           "A planar level set must be recovered exactly — "
                           + "the field is linear and so is the interpolation.")
        }
        // The box is 2 × 2 in the cut plane.
        XCTAssertEqual(area(triangles), 4.0, accuracy: 1e-9)
    }

    /// Winding: right-hand-rule normals must point along `outwardDirection` —
    /// renderers rely on it for lighting.
    func testTrianglesAreWoundToFaceOutward() {
        let triangles = sphere(radius: 1, resolution: 16)
        XCTAssertFalse(triangles.isEmpty)

        var checked = 0
        for base in stride(from: 0, to: triangles.count - 2, by: 3) {
            let a = triangles[base], b = triangles[base + 1], c = triangles[base + 2]
            let normal = simd_cross(b - a, c - a)
            guard simd_length(normal) > 1e-12 else { continue }
            let outward = (a + b + c) / 3          // radially out, for a sphere
            XCTAssertGreaterThan(simd_dot(simd_normalize(normal),
                                          simd_normalize(outward)), 0,
                                 "A triangle faces inward.")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 100, "Too few triangles to be meaningful.")
    }

    /// An unreached level produces nothing, not a degenerate sheet at the box wall.
    func testALevelOutsideTheFieldsRangeProducesNoSurface() {
        let triangles = Isosurface.triangles(
            level: 99,
            scalar: { simd_length($0) },
            outwardDirection: { $0 },
            center: .zero,
            extents: SIMD3(repeating: 2),
            resolution: 8)
        XCTAssertTrue(triangles.isEmpty)
    }

    /// The guard at the top: a grid needs at least one cell.
    func testAResolutionBelowTwoIsRefused() {
        for resolution in [-1, 0, 1] {
            XCTAssertTrue(Isosurface.triangles(
                level: 1,
                scalar: { simd_length($0) },
                outwardDirection: { $0 },
                center: .zero,
                extents: SIMD3(repeating: 4),
                resolution: resolution).isEmpty)
        }
    }
}
