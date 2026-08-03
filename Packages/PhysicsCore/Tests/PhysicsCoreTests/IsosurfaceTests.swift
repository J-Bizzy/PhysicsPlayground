//
//  IsosurfaceTests.swift
//  PhysicsCoreTests
//
//  `Isosurface` was the only type in PhysicsCore with no test at all —
//  148 lines of marching tetrahedra, while its two-dimensional sibling
//  `MarchingSquares` carries nine. Found by an inventory on 2026-08-03,
//  not by a failure.
//
//  The tests are geometry recovery, in the shape the rest of this
//  package uses: hand it a field whose level set is a surface we know
//  the exact area and position of, and measure what comes back. Nothing
//  here stores a reference triangle list — that would pin this
//  implementation rather than the mathematics, and a re-triangulation
//  that is just as correct would fail it.
//

import XCTest
import simd
@testable import PhysicsCore

final class IsosurfaceTests: XCTestCase {

    /// Sum of triangle areas — what a triangulation is FOR, and
    /// independent of how the surface happens to be cut up.
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

    /// **4πr².** The headline: a level set of |r| is a sphere, and its
    /// triangulated area has to converge on the closed form.
    ///
    /// A tolerance of 4 % at resolution 32, because a flat-faceted mesh
    /// INSCRIBED in a sphere always under-reports — this is discretisation
    /// error, not inaccuracy, and it has a sign.
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

    /// Refining the grid must move the answer toward the closed form,
    /// not merely near it. A constant offset would pass the test above
    /// at one resolution and is what this catches.
    func testRefiningTheGridConvergesOnTheTrueArea() {
        let exact = 4 * Double.pi
        let coarse = abs(area(sphere(radius: 1, resolution: 12)) - exact)
        let fine = abs(area(sphere(radius: 1, resolution: 32)) - exact)
        XCTAssertLessThan(fine, coarse,
                          "Error grew from \(coarse) to \(fine) as the grid "
                          + "was refined — that is not convergence.")
    }

    /// Every vertex must sit ON the level set to within the grid's own
    /// resolution. Area alone would tolerate a mesh of the right size in
    /// the wrong place.
    ///
    /// NOT to machine precision, and the reason is the interesting part.
    /// Crossing points are found by linear interpolation along a cell
    /// edge, which is exact only where the field is linear. |r| is not:
    /// along a chord the interpolated root sits slightly INSIDE the true
    /// arc, by O(h²). At resolution 16 over a 3.2 m box the cell is
    /// 0.2 m and the observed error is ~0.005 — second order, as it
    /// should be. The first draft of this test demanded 1e-9 and failed
    /// against a perfectly correct implementation.
    ///
    /// So: bounded by the discretisation, and — the part that actually
    /// pins the arithmetic — systematically inside rather than
    /// scattered, which is the signature of chord-versus-arc and not of
    /// a wrong root.
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
        // And it really is second order: the error is well under the
        // cell size, not merely under the bound above.
        XCTAssertLessThan(worst, cell * 0.1,
                          "Worst vertex error \(worst) against cell \(cell).")
    }

    /// A PLANE, where linear interpolation is exact and there is no
    /// discretisation error to hide behind: f(r) = r.x at level 0.25
    /// must come back as a flat sheet at exactly x = 0.25, with area
    /// equal to the box's cross-section.
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

    /// **Winding.** The header promises triangles wound so the
    /// right-hand-rule normal points along `outwardDirection`, and the
    /// modules that draw these rely on it for lighting. A surface with
    /// half its triangles inside out renders as a mesh full of holes.
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

    /// A level the field never reaches produces nothing, rather than a
    /// degenerate sheet at the box wall.
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
