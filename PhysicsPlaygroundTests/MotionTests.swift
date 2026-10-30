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

    /// `Motion.Spring`, the house throw: it swings past its target by about
    /// a fifth, settles to exactly the target, and has the same shape at any
    /// frame rate.
    func testTheSpringOvershootsAndSettles() {
        func run(_ dt: Double) -> (peak: Float, settled: Float, settledBy: Double) {
            var spring = Motion.Spring(0)
            var peak: Float = 0, time = 0.0, settledBy = -1.0
            while time < 1 {
                spring.step(toward: 1, dt: dt)
                peak = max(peak, spring.value)
                time += dt
                if settledBy < 0, spring.isSettled { settledBy = time }
            }
            return (peak, spring.value, settledBy)
        }
        let at90 = run(1.0 / 90)
        XCTAssertGreaterThan(at90.peak, 1.12, "it should swing past")
        XCTAssertLessThan(at90.peak, 1.30)
        XCTAssertEqual(at90.settled, 1, "must land exactly")
        XCTAssertGreaterThan(at90.settledBy, 0)
        XCTAssertLessThan(at90.settledBy, 0.8)
        let at45 = run(1.0 / 45)
        XCTAssertEqual(at45.peak, at90.peak, accuracy: 0.02, "the throw must not depend on the frame rate")
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
