//
//  FanLayoutTests.swift
//  PhysicsPlaygroundTests
//
//  The fan is now the app's only N-way picker (DECISIONS.md,
//  2026-07-29), so every module's choices will pass through this
//  arithmetic. The failures worth catching here are the ones that only
//  show up on device: a fan that overlaps itself, opens through the floor,
//  or divides by a zero item count.
//

import XCTest
import simd
import RenderKit

final class FanLayoutTests: XCTestCase {

    // MARK: Opening and closing

    func testClosedFanPlacesNothingVisible() {
        let fan = FanLayout()
        for index in 0..<6 {
            let placement = fan.placement(index: index, count: 6, openness: 0)
            XCTAssertFalse(placement.isVisible)
            XCTAssertEqual(placement.progress, 0)
        }
    }

    /// Fully open, every item has arrived and sits at full scale — no
    /// residual overshoot left over from the pop.
    func testFullyOpenFanHasEveryItemLanded() {
        let fan = FanLayout()
        for index in 0..<6 {
            let placement = fan.placement(index: index, count: 6, openness: 1)
            XCTAssertTrue(placement.isVisible)
            XCTAssertEqual(placement.progress, 1, accuracy: 1e-12)
            XCTAssertEqual(placement.scale, 1, accuracy: 1e-12,
                           "the pop must ease back to exactly 1")
        }
    }

    /// The stagger is the point: items arrive in order, so a fan reads as
    /// unfolding rather than appearing.
    func testItemsArriveInOrder() {
        let fan = FanLayout()
        let progresses = (0..<6).map {
            fan.placement(index: $0, count: 6, openness: 0.5).progress
        }
        for (earlier, later) in zip(progresses, progresses.dropFirst()) {
            XCTAssertGreaterThan(earlier, later, "earlier items lead")
        }
    }

    // MARK: Geometry

    /// The fan spreads symmetrically about its anchor, so it doesn't lean.
    func testFanIsSymmetricAboutTheCentre() {
        let fan = FanLayout()
        let first = fan.placement(index: 0, count: 5, openness: 1).offset
        let last = fan.placement(index: 4, count: 5, openness: 1).offset
        XCTAssertEqual(first.x, -last.x, accuracy: 1e-12)
        XCTAssertEqual(first.y, last.y, accuracy: 1e-12)
    }

    /// It opens UPWARD. Every item must sit at or above the anchor —
    /// a 150° span squashed vertically should never dip below it, because
    /// below is where the apparatus and the floor are.
    func testFanNeverOpensDownward() {
        let fan = FanLayout()
        for count in [1, 2, 3, 5, 9, 12] {
            for index in 0..<count {
                for openness in stride(from: 0.0, through: 1.0, by: 0.05) {
                    let y = fan.placement(index: index, count: count,
                                          openness: openness).offset.y
                    XCTAssertGreaterThanOrEqual(
                        y, 0, "count \(count) item \(index) dipped to \(y)")
                }
            }
        }
    }

    /// Neighbouring items must not land on top of each other, or the fan
    /// becomes an unreadable pile — the exact failure that made the old
    /// palette ring go from a 0.26 m radius to 0.40 m.
    func testNeighboursAreSeparatedAtFullOpen() {
        let fan = FanLayout()
        // Disc radius is 0.026 m, so centres need to clear ~0.052 m.
        let discDiameter = 0.052
        for count in 2...9 {
            let offsets = (0..<count).map {
                fan.placement(index: $0, count: count, openness: 1).offset
            }
            for (a, b) in zip(offsets, offsets.dropFirst()) {
                XCTAssertGreaterThan(
                    simd_distance(a, b), discDiameter,
                    "with \(count) items, neighbours overlap")
            }
        }
    }

    /// Every item sits within reach — a picker you have to walk to is not
    /// a picker.
    func testItemsStayWithinReach() {
        let fan = FanLayout()
        for count in 1...12 {
            for index in 0..<count {
                let offset = fan.placement(index: index, count: count,
                                           openness: 1).offset
                XCTAssertLessThan(simd_length(offset), 0.40)
            }
        }
    }

    // MARK: Degenerate counts

    /// One item goes to the middle, not to one end of the span. Dividing
    /// the span by count−1 would be a divide by zero here, and NaN
    /// propagates through every transform downstream.
    func testSingleItemSitsCentredAndFinite() {
        let placement = FanLayout().placement(index: 0, count: 1, openness: 1)
        XCTAssertEqual(placement.offset.x, 0, accuracy: 1e-12)
        XCTAssertTrue(placement.offset.x.isFinite)
        XCTAssertTrue(placement.offset.y.isFinite)
        XCTAssertGreaterThan(placement.offset.y, 0)
    }

    func testZeroCountIsFiniteRatherThanCrashing() {
        let placement = FanLayout().placement(index: 0, count: 0, openness: 1)
        XCTAssertTrue(placement.offset.x.isFinite)
        XCTAssertTrue(placement.offset.y.isFinite)
    }

    /// Openness outside 0…1 is clamped rather than extrapolated — a
    /// smoothing overshoot must not fling the fan out of the room.
    func testOpennessIsClamped() {
        let fan = FanLayout()
        let over = fan.placement(index: 0, count: 4, openness: 4.0)
        let under = fan.placement(index: 0, count: 4, openness: -2.0)
        XCTAssertEqual(over.progress, 1, accuracy: 1e-12)
        XCTAssertEqual(under.progress, 0, accuracy: 1e-12)
    }

    // MARK: Easing

    func testEasingConvergesAndSnaps() {
        var openness = 0.0
        for _ in 0..<200 {
            openness = FanLayout.ease(openness, toward: 1, dt: 1.0 / 90)
        }
        XCTAssertEqual(openness, 1, accuracy: 1e-12, "must snap, not approach")
    }

    func testEasingClosesCompletely() {
        var openness = 1.0
        for _ in 0..<200 {
            openness = FanLayout.ease(openness, toward: 0, dt: 1.0 / 90)
        }
        XCTAssertEqual(openness, 0, accuracy: 1e-12)
    }

    /// A long frame must not overshoot past the target and bounce.
    func testAHugeTimestepDoesNotOvershoot() {
        let openness = FanLayout.ease(0, toward: 1, dt: 10)
        XCTAssertEqual(openness, 1, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(openness, 1)
    }

    /// Easing is frame-rate independent: 90 Hz and 45 Hz reach
    /// substantially the same place over the same wall-clock time.
    func testEasingIsFrameRateIndependent() {
        var fast = 0.0
        for _ in 0..<90 { fast = FanLayout.ease(fast, toward: 1, dt: 1.0 / 90) }
        var slow = 0.0
        for _ in 0..<45 { slow = FanLayout.ease(slow, toward: 1, dt: 1.0 / 45) }
        XCTAssertEqual(fast, slow, accuracy: 0.02)
    }
}
