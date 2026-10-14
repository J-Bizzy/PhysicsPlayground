//
//  MotionTests.swift
//  PhysicsPlaygroundTests
//
//  `Motion.ease`, the app's one ease: converge and snap, never
//  overshoot, frame-rate independent. Reduce Motion is a system switch
//  these tests cannot flip, so only the un-reduced path is asserted;
//  `MotionCriterionTests` covers the other half.
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
