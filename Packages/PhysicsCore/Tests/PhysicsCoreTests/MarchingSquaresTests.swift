//
//  MarchingSquaresTests.swift
//  Contour extraction checked against exact circles: every vertex must land ON the level.
//

import XCTest
import simd
@testable import PhysicsCore

final class MarchingSquaresTests: XCTestCase {

    /// f(x,y) = |p|: the level-r contour is the circle of radius r, every vertex on it.
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

    func testContourLengthMatchesTheCircumference() {
        let radius = 0.6
        let segments = MarchingSquares.contour(
            level: radius,
            scalar: { simd_length($0) },
            center: .zero, extents: SIMD2(2, 2), resolution: 96)
        let total = segments.reduce(0.0) { $0 + simd_distance($1.a, $1.b) }
        XCTAssertEqual(total, 2 * .pi * radius, accuracy: 0.02)
    }

    func testLevelOutsideTheFieldRangeProducesNoSegments() {
        let segments = MarchingSquares.contour(
            level: 99,
            scalar: { simd_length($0) },
            center: .zero, extents: SIMD2(2, 2), resolution: 16)
        XCTAssertTrue(segments.isEmpty)
    }

    func testConstantFieldHasNoContour() {
        let segments = MarchingSquares.contour(
            level: 0.5, scalar: { _ in 1.0 },
            center: .zero, extents: SIMD2(2, 2), resolution: 16)
        XCTAssertTrue(segments.isEmpty)
    }

    /// Linear interpolation reproduces a linear field exactly: contour is x = level to 1e-12.
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

    /// A closed contour welds into ONE polyline, not 200 sticks.
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

    /// Chaining must never bridge across a gap between separate contours.
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
