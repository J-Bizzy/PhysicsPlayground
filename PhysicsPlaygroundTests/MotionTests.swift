//
//  MotionTests.swift
//  PhysicsPlaygroundTests
//
//  `Motion.ease` is the app's ONE ease, inherited wholesale from
//  `FanLayout.ease` along with these tests. The arithmetic is unchanged
//  and so are its guarantees — converge and snap, never overshoot,
//  frame-rate independent — which is the point of moving them rather
//  than writing new ones: the replacement has to be the same function,
//  plus the Reduce Motion behaviour the original lacked.
//
//  The setting itself is a system switch these tests cannot flip, so
//  what is asserted here is the un-reduced path. `MotionCriterionTests`
//  covers the other half by banning hand-rolled eases outright, which is
//  the part that actually went wrong: six of eight primitives never
//  called any shared helper at all.
//

import XCTest
import RenderKit

@MainActor
final class MotionTests: XCTestCase {


    func testEasingConvergesAndSnaps() {
        var openness = 0.0
        for _ in 0..<200 {
            openness = Motion.ease(openness, toward: 1, dt: 1.0 / 90)
        }
        XCTAssertEqual(openness, 1, accuracy: 1e-12, "must snap, not approach")
    }

    func testEasingClosesCompletely() {
        var openness = 1.0
        for _ in 0..<200 {
            openness = Motion.ease(openness, toward: 0, dt: 1.0 / 90)
        }
        XCTAssertEqual(openness, 0, accuracy: 1e-12)
    }

    /// A long frame must not overshoot past the target and bounce.
    func testAHugeTimestepDoesNotOvershoot() {
        let openness: Double = Motion.ease(0, toward: 1, dt: 10)
        XCTAssertEqual(openness, 1, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(openness, 1)
    }

    /// Easing is frame-rate independent: 90 Hz and 45 Hz reach
    /// substantially the same place over the same wall-clock time.
    func testEasingIsFrameRateIndependent() {
        var fast = 0.0
        for _ in 0..<90 { fast = Motion.ease(fast, toward: 1, dt: 1.0 / 90) }
        var slow = 0.0
        for _ in 0..<45 { slow = Motion.ease(slow, toward: 1, dt: 1.0 / 45) }
        XCTAssertEqual(fast, slow, accuracy: 0.02)
    }
}
