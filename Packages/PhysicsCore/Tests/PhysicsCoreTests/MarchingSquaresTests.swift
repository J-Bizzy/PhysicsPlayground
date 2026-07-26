//
//  MarchingSquaresTests.swift
//  PhysicsCoreTests
//
//  Contours have to land ON the level, not near it — an interpolated
//  crossing is the whole difference between a smooth curve and a
//  staircase. Circles are the honest test case: an exact answer to
//  compare every extracted vertex against.
//

import XCTest
import simd
@testable import PhysicsCore

final class MarchingSquaresTests: XCTestCase {

    /// f(x,y) = |p| — the contour at level r must be the circle of
    /// radius r, and EVERY vertex must sit on it to interpolation
    /// accuracy.
    func testContourOfARadialFieldIsACircleOfTheRightRadius() {
        let radius = 0.6
        let segments = MarchingSquares.contour(
            level: radius,
            scalar: { simd_length($0) },
            center: .zero, extents: SIMD2(2, 2), resolution: 64)

        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            for point in [segment.a, segment.b] {
                XCTAssertEqual(simd_length(point), radius, accuracy: 2e-3,
                               "every contour vertex lies on the iso-level")
            }
        }
    }

    /// And the total arc length of that contour is 2πr.
    func testContourLengthMatchesTheCircumference() {
        let radius = 0.6
        let segments = MarchingSquares.contour(
            level: radius,
            scalar: { simd_length($0) },
            center: .zero, extents: SIMD2(2, 2), resolution: 96)
        let total = segments.reduce(0.0) { $0 + simd_distance($1.a, $1.b) }
        XCTAssertEqual(total, 2 * .pi * radius, accuracy: 0.02)
    }

    /// A level nothing reaches produces nothing — no spurious geometry.
    func testLevelOutsideTheFieldRangeProducesNoSegments() {
        let segments = MarchingSquares.contour(
            level: 99,
            scalar: { simd_length($0) },
            center: .zero, extents: SIMD2(2, 2), resolution: 16)
        XCTAssertTrue(segments.isEmpty)
    }

    /// A constant field has no contour anywhere — every cell is entirely
    /// inside or entirely outside.
    func testConstantFieldHasNoContour() {
        let segments = MarchingSquares.contour(
            level: 0.5, scalar: { _ in 1.0 },
            center: .zero, extents: SIMD2(2, 2), resolution: 16)
        XCTAssertTrue(segments.isEmpty)
    }

    /// Linear ramp: the contour is the straight line x = level, and it
    /// must be exact — linear interpolation reproduces a linear field
    /// with no error at all.
    func testLinearRampGivesAnExactStraightContour() {
        let level = 0.31
        let segments = MarchingSquares.contour(
            level: level, scalar: { $0.x },
            center: .zero, extents: SIMD2(2, 2), resolution: 8)
        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            XCTAssertEqual(segment.a.x, level, accuracy: 1e-12)
            XCTAssertEqual(segment.b.x, level, accuracy: 1e-12)
        }
    }

    /// Resolution refines the answer rather than changing it.
    func testFinerResolutionConvergesOnTheCircle() {
        func error(resolution: Int) -> Double {
            MarchingSquares.contour(
                level: 0.5, scalar: { simd_length($0) },
                center: .zero, extents: SIMD2(2, 2), resolution: resolution)
                .map { abs(simd_length($0.a) - 0.5) }
                .max() ?? 0
        }
        XCTAssertLessThan(error(resolution: 64), error(resolution: 12))
    }

    // MARK: Chaining

    /// A closed circular contour welds into a single loop, not 200 sticks.
    func testChainingJoinsACircleIntoOnePolyline() {
        let segments = MarchingSquares.contour(
            level: 0.5, scalar: { simd_length($0) },
            center: .zero, extents: SIMD2(2, 2), resolution: 48)
        let chained = MarchingSquares.chain(segments, tolerance: 1e-9)
        XCTAssertEqual(chained.count, 1, "one closed contour, one polyline")
        XCTAssertGreaterThan(chained[0].count, 40)
        XCTAssertEqual(simd_distance(chained[0].first!, chained[0].last!), 0,
                       accuracy: 1e-9, "and it closes on itself")
    }

    /// Two separate circles stay two separate polylines — chaining must
    /// never bridge across a gap.
    func testChainingKeepsSeparateContoursSeparate() {
        let left = SIMD2<Double>(-0.6, 0), right = SIMD2<Double>(0.6, 0)
        let segments = MarchingSquares.contour(
            level: 0.25,
            scalar: { min(simd_distance($0, left), simd_distance($0, right)) },
            center: .zero, extents: SIMD2(2.4, 1.6), resolution: 96)
        let chained = MarchingSquares.chain(segments, tolerance: 1e-9)
        XCTAssertEqual(chained.count, 2)
    }

    func testChainingEmptyInputIsEmpty() {
        XCTAssertTrue(MarchingSquares.chain([]).isEmpty)
    }
}
