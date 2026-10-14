//
//  StationBoxTests.swift
//  PhysicsCore — tests
//
//  The box math every multi-station layout asserts against. If these
//  are wrong, the layout tests that depend on them pass while two
//  apparatus quietly share a cubic metre.
//

import XCTest
import simd
@testable import PhysicsCore

final class StationBoxTests: XCTestCase {

    // MARK: Disjointness

    /// Clearance on one axis is enough — these are axis-aligned boxes,
    /// so a single clear axis proves no overlap however much the other
    /// two interpenetrate. This is the property the whole arc relies on.
    func testSeparationOnASingleAxisIsEnough() {
        let left = StationBox(center: SIMD3(-1, 1.25, -0.9),
                              halfExtents: SIMD3(0.4, 0.5, 0.4))
        // Overlaps completely in y and z; in x they span [-1.4, -0.6]
        // and [-0.2, 0.6], so the gap is 0.4.
        let right = StationBox(center: SIMD3(0.2, 1.25, -0.9),
                               halfExtents: SIMD3(0.4, 0.5, 0.4))
        XCTAssertEqual(left.separation(from: right), 0.4, accuracy: 1e-12)
        XCTAssertTrue(left.isSeparated(from: right, margin: 0.05))
        XCTAssertFalse(left.isSeparated(from: right, margin: 0.5))
    }

    func testSeparationIsSymmetric() {
        let a = StationBox(center: SIMD3(-0.72, 1.25, -0.9),
                           halfExtents: SIMD3(0.72, 0.5, 0.38))
        let b = StationBox(center: SIMD3(0.72, 1.35, -0.9),
                           halfExtents: SIMD3(0.65, 0.85, 0.66))
        XCTAssertEqual(a.separation(from: b), b.separation(from: a),
                       accuracy: 1e-12)
    }

    /// Overlapping boxes report a negative gap, and the magnitude is how
    /// far they interpenetrate on the least-bad axis — so a failing
    /// layout test can say how much it missed by.
    func testOverlapReportsNegativeSeparation() {
        let a = StationBox(center: .zero, halfExtents: SIMD3(repeating: 0.5))
        let b = StationBox(center: SIMD3(0.2, 0, 0),
                           halfExtents: SIMD3(repeating: 0.5))
        XCTAssertEqual(a.separation(from: b), -0.8, accuracy: 1e-12)
        XCTAssertFalse(a.isSeparated(from: b))
    }

    /// Boxes touching exactly face-to-face have zero gap: separated at
    /// margin 0, not separated at any positive clearance.
    func testTouchingFacesAreZeroSeparation() {
        let a = StationBox(center: .zero, halfExtents: SIMD3(repeating: 0.5))
        let b = StationBox(center: SIMD3(1, 0, 0),
                           halfExtents: SIMD3(repeating: 0.5))
        XCTAssertEqual(a.separation(from: b), 0, accuracy: 1e-12)
        XCTAssertTrue(a.isSeparated(from: b, margin: 0))
        XCTAssertFalse(a.isSeparated(from: b, margin: 0.01))
    }

    // MARK: Containment

    func testContainmentOfPointsAndBoxes() {
        let station = StationBox(center: SIMD3(0, 1.35, -0.9),
                                 halfExtents: SIMD3(0.62, 0.65, 0.6))
        XCTAssertTrue(station.contains(SIMD3(0, 1.35, -0.9)))
        XCTAssertTrue(station.contains(SIMD3(0.62, 1.35, -0.9)), "a face is inside")
        XCTAssertFalse(station.contains(SIMD3(0.63, 1.35, -0.9)))

        let clamp = StationBox(center: SIMD3(0, 1.35, -0.9),
                               halfExtents: SIMD3(0.5, 0.5, 0.5))
        XCTAssertTrue(station.contains(clamp))
        XCTAssertFalse(clamp.contains(station))
    }

    /// A station's box is declared in its module's own coordinates and
    /// then carried to its seat, so offsetting has to be exact — the
    /// layouts compute containment on the moved box.
    func testOffsetMovesTheCentreAndKeepsTheSize() {
        let box = StationBox(center: SIMD3(0, 1.35, -0.7),
                             halfExtents: SIMD3(0.65, 0.85, 0.66))
        let moved = box.offset(by: SIMD3(0.72, 0, -0.2))
        XCTAssertEqual(simd_distance(moved.center, SIMD3(0.72, 1.35, -0.9)), 0,
                       accuracy: 1e-12)
        XCTAssertEqual(moved.halfExtents, box.halfExtents)
    }

    /// Negative half-extents are a typo, not a request for an inside-out
    /// box — normalising them keeps `minimum` below `maximum` so every
    /// other function stays meaningful.
    func testNegativeHalfExtentsAreNormalised() {
        let box = StationBox(center: .zero, halfExtents: SIMD3(-0.5, 0.5, -0.5))
        XCTAssertEqual(box.halfExtents, SIMD3(0.5, 0.5, 0.5))
        XCTAssertTrue(box.minimum.x <= box.maximum.x)
    }

    // MARK: Radial reach

    /// The near end is zero when the point is inside the box; the far end
    /// is always the most distant corner. Both are needed to seat a bench
    /// inside an orrery's empty shell.
    func testDistanceRangeFromAPointInside() {
        let box = StationBox(center: .zero, halfExtents: SIMD3(repeating: 1))
        let (near, far) = box.distanceRange(from: .zero)
        XCTAssertEqual(near, 0, accuracy: 1e-12)
        XCTAssertEqual(far, (3.0 as Double).squareRoot(), accuracy: 1e-12,
                       "the far end is the corner, not the face")
    }

    func testDistanceRangeFromAPointOutside() {
        // A unit cube centred at x = 3: nearest face at 2, farthest
        // corner at sqrt(4^2 + 1 + 1).
        let box = StationBox(center: SIMD3(3, 0, 0),
                             halfExtents: SIMD3(repeating: 1))
        let (near, far) = box.distanceRange(from: .zero)
        XCTAssertEqual(near, 2, accuracy: 1e-12)
        XCTAssertEqual(far, (18.0 as Double).squareRoot(), accuracy: 1e-12)
    }

    /// The diagonal case: outside on two axes at once, so the near
    /// distance is a corner distance rather than a face distance.
    func testDistanceRangeIsEuclideanNotPerAxis() {
        let box = StationBox(center: SIMD3(3, 4, 0),
                             halfExtents: SIMD3(repeating: 1))
        let (near, _) = box.distanceRange(from: .zero)
        // Nearest corner sits at (2, 3, 0).
        XCTAssertEqual(near, (13.0 as Double).squareRoot(), accuracy: 1e-12)
    }
}
