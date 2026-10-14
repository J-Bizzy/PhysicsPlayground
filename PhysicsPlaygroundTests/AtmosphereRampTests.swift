//
//  AtmosphereRampTests.swift
//  PhysicsPlaygroundTests
//
//  The room changes brightness over time, not in a frame. Tests on
//  `RoomDimmerView.step`, a pure Double → Double.
//  `testTheRampNeverLeavesTheInterval` is a standing ban on using the
//  shell as a dip-to-dark transition: the ramp texture caps alpha, so a
//  slam to 1.0 is heavy smoke rather than a curtain.
//

import XCTest
import UIKit
@testable import PhysicsPlayground

@MainActor
final class AtmosphereRampTests: XCTestCase {

    /// The house frame at 90 Hz.
    private let frame = 1.0 / 90.0

    override func setUpWithError() throws {
        // Every assertion below is about easing; Reduce Motion jumps by
        // contract and is asserted separately.
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled,
                      "Reduce Motion is on; the ramp is a jump by contract.")
    }

    // MARK: It moves, and it does not arrive at once

    func testOneFrameMovesTowardTheTargetWithoutArriving() {
        let next = RoomDimmerView.step(shown: 0, toward: 0.35, dt: frame)
        XCTAssertGreaterThan(next, 0, "a frame of ramp should move")
        XCTAssertLessThan(next, 0.35, "and should not land in one frame")
    }

    /// Orbital Mechanics' 0.85 against the hub's 0 is the largest step the app
    /// can make, and the one that used to slam hardest.
    func testTheLargestStepInTheAppStillTakesTime() {
        let next = RoomDimmerView.step(shown: 0, toward: 0.85, dt: frame)
        XCTAssertLessThan(next, 0.85)
    }

    // MARK: It arrives, exactly

    func testItArrivesExactlyRatherThanApproachingForever() {
        var shown = 0.0
        for _ in 0..<120 {
            shown = RoomDimmerView.step(shown: shown, toward: 0.35, dt: frame)
        }
        // Exact equality: `Motion.ease` snaps inside 0.004 so a shell never
        // sits fractionally open.
        XCTAssertEqual(shown, 0.35)
    }

    func testItArrivesExactlyOnTheWayDownToo() {
        var shown = 0.85
        for _ in 0..<120 {
            shown = RoomDimmerView.step(shown: shown, toward: 0, dt: frame)
        }
        XCTAssertEqual(shown, 0)
    }

    /// A settled shell is written every frame; the write must be idempotent
    /// or the "no per-frame work once settled" claim in the header is false.
    func testASettledRampIsAFixedPoint() {
        let settled = RoomDimmerView.step(shown: 0.35, toward: 0.35, dt: frame)
        XCTAssertEqual(settled, 0.35)
    }

    // MARK: The standing ban

    /// The ramp may never leave the interval between where it is and where
    /// it is going: no overshoot, no excursion toward dark. Swept, because
    /// the failures are at the edges.
    func testTheRampNeverLeavesTheInterval() {
        let levels = [0.0, 0.01, 0.02, 0.35, 0.5, 0.85, 0.99, 1.0]
        let steps = [1.0 / 120, frame, 1.0 / 30, 0.1, 0.5, 1.0]

        for shown in levels {
            for target in levels {
                for dt in steps {
                    let next = RoomDimmerView.step(shown: shown,
                                                   toward: target, dt: dt)
                    XCTAssertGreaterThanOrEqual(
                        next, min(shown, target),
                        "ramp \(shown)→\(target) at dt \(dt) undershot to \(next)")
                    XCTAssertLessThanOrEqual(
                        next, max(shown, target),
                        "ramp \(shown)→\(target) at dt \(dt) overshot to \(next)")
                }
            }
        }
    }

    /// A long stall must not teleport past the target either — the frame
    /// clock is not guaranteed and `min(dt * rate, 1)` is what holds it.
    func testAStalledFrameStillLandsInsideTheInterval() {
        let next = RoomDimmerView.step(shown: 0, toward: 0.35, dt: 10)
        XCTAssertLessThanOrEqual(next, 0.35)
        XCTAssertGreaterThanOrEqual(next, 0)
    }
}

/// Reduce Motion runs the other way, so it gets its own case with the
/// inverted skip — the same shape `FadeTests` uses.
@MainActor
final class AtmosphereRampReduceMotionTests: XCTestCase {

    func testReduceMotionArrivesAtOnce() throws {
        try XCTSkipUnless(UIAccessibility.isReduceMotionEnabled,
                          "Requires Reduce Motion on.")
        // Somebody who asks the room to stop changing brightness wants it to
        // stop, not to change more smoothly.
        XCTAssertEqual(RoomDimmerView.step(shown: 0, toward: 0.85,
                                           dt: 1.0 / 90.0), 0.85)
    }
}
