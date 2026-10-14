//
//  RoomBoxTests.swift
//  PhysicsCoreTests
//
//  Clipping is what makes virtual light stop at a real wall, so it has
//  to be exact: crossings land on the boundary, a line that leaves and
//  returns comes back as two runs, and a segment that only cuts a corner
//  still contributes its piece.
//

import XCTest
import simd
@testable import PhysicsCore

final class RoomBoxTests: XCTestCase {

    /// A 2 × 2 × 2 m box centred on the origin — easy exact arithmetic.
    private let box = RoomBox(center: .zero, halfExtents: SIMD3(1, 1, 1))

    func testContainsIsInclusiveOfTheBoundary() {
        XCTAssertTrue(box.contains(SIMD3(0, 0, 0)))
        XCTAssertTrue(box.contains(SIMD3(1, 1, 1)), "corner counts as inside")
        XCTAssertFalse(box.contains(SIMD3(1.0001, 0, 0)))
    }

    func testExitPointLandsExactlyOnTheWall() {
        let exit = box.exitPoint(from: SIMD3(0, 0, 0), towards: SIMD3(5, 0, 0))
        XCTAssertNotNil(exit)
        XCTAssertEqual(exit!.x, 1, accuracy: 1e-12, "stops exactly at x = +1")
        XCTAssertEqual(exit!.y, 0, accuracy: 1e-12)
        XCTAssertEqual(exit!.z, 0, accuracy: 1e-12)
    }

    /// A diagonal exit hits the first slab it reaches, not the far one.
    func testExitPointTakesTheNearestWall() {
        let exit = box.exitPoint(from: SIMD3(0, 0, 0), towards: SIMD3(4, 1, 0))
        XCTAssertNotNil(exit)
        XCTAssertEqual(exit!.x, 1, accuracy: 1e-12)
        XCTAssertEqual(exit!.y, 0.25, accuracy: 1e-12, "y advances a quarter as fast")
    }

    func testRayThatMissesTheBoxHasNoInterval() {
        XCTAssertNil(box.rayInterval(origin: SIMD3(0, 5, 0), direction: SIMD3(1, 0, 0)))
    }

    // MARK: Polyline clipping

    func testFullyInsidePolylineSurvivesUntouched() {
        let line = [SIMD3<Double>(-0.5, 0, 0), SIMD3(0, 0, 0), SIMD3(0.5, 0, 0)]
        let runs = box.clip(polyline: line)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].count, 3)
    }

    func testPolylineLeavingTheBoxIsTruncatedAtTheWall() {
        let line = [SIMD3<Double>(0, 0, 0), SIMD3(3, 0, 0)]
        let runs = box.clip(polyline: line)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].last!.x, 1, accuracy: 1e-12,
                       "the line ends on the wall, not three metres past it")
    }

    /// The property the field-line renderers actually depend on: a line
    /// that exits and re-enters must not be joined across the gap.
    func testPolylineLeavingAndReturningYieldsTwoRuns() {
        let line = [
            SIMD3<Double>(0, 0, 0),
            SIMD3(0, 3, 0),      // out through the ceiling
            SIMD3(0.5, 3, 0),
            SIMD3(0.5, 0, 0),    // back in through the ceiling
        ]
        let runs = box.clip(polyline: line)
        XCTAssertEqual(runs.count, 2, "two separate pieces, not one bridged line")
        XCTAssertEqual(runs[0].last!.y, 1, accuracy: 1e-12)
        XCTAssertEqual(runs[1].first!.y, 1, accuracy: 1e-12)
    }

    func testFullyOutsidePolylineIsDropped() {
        let line = [SIMD3<Double>(0, 5, 0), SIMD3(3, 5, 0)]
        XCTAssertTrue(box.clip(polyline: line).isEmpty)
    }

    /// Both endpoints outside, but the segment passes through the box:
    /// the crossing piece must survive.
    func testSegmentCuttingThroughFromOutsideKeepsItsInteriorPiece() {
        let line = [SIMD3<Double>(-3, 0, 0), SIMD3(3, 0, 0)]
        let runs = box.clip(polyline: line)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0][0].x, -1, accuracy: 1e-12)
        XCTAssertEqual(runs[0][1].x, 1, accuracy: 1e-12)
    }

    // MARK: Building

    func testEnclosingHonoursAMinimumSoAThinScanIsNotASliver() {
        // Two points that differ only in x: without the floor, y and z
        // would collapse to zero half-extent.
        let room = RoomBox.enclosing(points: [SIMD3(-2, 1, 0), SIMD3(2, 1, 0)],
                                     minimumHalfExtents: SIMD3(1.2, 1.0, 1.2))
        XCTAssertEqual(room.halfExtents.x, 2, accuracy: 1e-12)
        XCTAssertEqual(room.halfExtents.y, 1.0, accuracy: 1e-12)
        XCTAssertEqual(room.halfExtents.z, 1.2, accuracy: 1e-12)
    }

    func testEnclosingWithNoPointsFallsBackToTheUnscannedRoom() {
        XCTAssertEqual(RoomBox.enclosing(points: []), RoomBox.unscanned)
    }

    func testInsetShrinksEverySideAndNeverCollapses() {
        XCTAssertEqual(box.inset(by: 0.25).halfExtents.x, 0.75, accuracy: 1e-12)
        XCTAssertEqual(box.inset(by: 99).halfExtents.x, 0.001, accuracy: 1e-12)
    }
    // MARK: Look-ray placement

    /// A reach inside the box is honoured exactly.
    func testPointOnRayUsesTheRequestedReachWhenItFits() {
        let point = box.point(onRay: SIMD3(0, 0, -3), direction: SIMD3(0, 0, 1), reach: 3.5)
        XCTAssertNotNil(point)
        XCTAssertEqual(point!.z, 0.5, accuracy: 1e-12)
    }

    /// Reaching past the far wall stops at the far wall — you cannot
    /// measure a field outside the region that holds it.
    func testPointOnRayIsPulledBackToTheFarWall() {
        let point = box.point(onRay: SIMD3(0, 0, -3), direction: SIMD3(0, 0, 1), reach: 99)
        XCTAssertNotNil(point)
        XCTAssertEqual(point!.z, 1, accuracy: 1e-12)
    }

    /// Too short a reach is pushed forward to where the ray enters, so
    /// the probe never sits behind the experiment.
    func testPointOnRayIsPushedForwardToTheNearWall() {
        let point = box.point(onRay: SIMD3(0, 0, -3), direction: SIMD3(0, 0, 1), reach: 0.5)
        XCTAssertNotNil(point)
        XCTAssertEqual(point!.z, -1, accuracy: 1e-12)
    }

    /// Looking away from the experiment measures nothing rather than
    /// reporting a number about empty air.
    func testPointOnRayIsNilWhenTheRayMissesTheBox() {
        XCTAssertNil(box.point(onRay: SIMD3(0, 5, -3), direction: SIMD3(0, 0, 1), reach: 3))
    }

    /// And nothing behind the viewer counts, even if the box is there.
    func testPointOnRayIgnoresWhatIsBehindTheViewer() {
        XCTAssertNil(box.point(onRay: SIMD3(0, 0, -3), direction: SIMD3(0, 0, -1), reach: 3))
    }

    func testPointOnRayNeedsARealDirection() {
        XCTAssertNil(box.point(onRay: .zero, direction: .zero, reach: 1))
    }
}
