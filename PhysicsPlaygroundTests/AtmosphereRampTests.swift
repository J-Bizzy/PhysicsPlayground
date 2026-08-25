//
//  AtmosphereRampTests.swift
//  PhysicsPlaygroundTests
//
//  THE ROOM CHANGES BRIGHTNESS OVER TIME, NOT IN A FRAME.
//
//  `AtmosphereCriterionTests` settled what the six labs' brightness values
//  are, and its header says why it matters: "In a demo cut between labs it
//  is the loudest difference between two rooms that are supposed to feel
//  like one place." It could not reach the STEP between two of those
//  values, because there wasn't one — `adoptModuleAtmosphere` assigned the
//  level and `RoomDimmerView` wrote it straight into an OpacityComponent.
//  Twice per lab visit, the wearer's actual living room jumped.
//
//  These tests are on `RoomDimmerView.step`, which is a pure Double →
//  Double so none of this needs a scene, a headset, or a simulator.
//
//  ONE OF THEM IS A STANDING BAN. `testTheRampNeverLeavesTheInterval`
//  encodes a design that was proposed, built toward, and rejected: using
//  the dimming shell as a dip-to-dark transition medium, slamming the level
//  toward 1.0 during a scene swap and back down after. It cannot work — the
//  ramp texture caps alpha at 235/255 under `.transparent(opacity: 0.9)`,
//  so even at 1.0 the shell is a heavy smoke rather than a curtain, and
//  Gravity Lab's Sun reads straight through it — and it would transiently
//  violate `AtmosphereCriterionTests.testAModuleThatDimsHeavilyAlsoMovesItsShellOut`
//  on entry to all six modules. A comment saying "don't do that" is a
//  comment. A swept property is a test.
//

import XCTest
import UIKit
@testable import PhysicsPlayground

@MainActor
final class AtmosphereRampTests: XCTestCase {

    /// The house frame at 90 Hz.
    private let frame = 1.0 / 90.0

    override func setUpWithError() throws {
        // Every assertion below is about easing. Under Reduce Motion the
        // house ease jumps by contract, which is correct behaviour and is
        // asserted separately in `testReduceMotionArrivesAtOnce`.
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled,
                      "Reduce Motion is on; the ramp is a jump by contract.")
    }

    // MARK: It moves, and it does not arrive at once

    func testOneFrameMovesTowardTheTargetWithoutArriving() {
        let next = RoomDimmerView.step(shown: 0, toward: 0.35, dt: frame)
        XCTAssertGreaterThan(next, 0, "a frame of ramp should move")
        XCTAssertLessThan(next, 0.35, "and should not land in one frame")
    }

    /// Gravity Lab's 0.85 against the hub's 0 is the largest step the app
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
        // EXACT equality, not an accuracy window. `Motion.ease` snaps inside
        // 0.004 precisely so a shell never sits fractionally open, and a
        // test with a tolerance would not notice if that snap were lost.
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

    /// THE REJECTED DESIGN, ENCODED. The ramp may never leave the interval
    /// between where it is and where it is going — no overshoot, and above
    /// all no excursion toward dark on the way to a lighter target. Swept
    /// rather than sampled, because the interesting failures are at the
    /// edges: dt far larger than a frame, targets at both ends, and a step
    /// that starts above its target.
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
