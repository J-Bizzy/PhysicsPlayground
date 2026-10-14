//
//  PressLatchTests.swift
//  PhysicsPlaygroundTests
//
//  A press that never travels must never promote; a press that travels
//  must promote exactly once; a cancelled press must be unable to
//  promote later. The gesture wiring itself is headset-only; this is
//  the decision it defers to.
//

import XCTest
import RenderKit
import simd

final class PressLatchTests: XCTestCase {

    private let start = SIMD3<Double>(0.2, 1.3, -0.9)

    // MARK: A tap must not act

    /// A hand held as still as a hand can be, for a second. Ninety
    /// frames of drift must not add up to a grab.
    func testAStillPressNeverPromotes() {
        var latch = PressLatch<String>()
        latch.press("bob", at: start)

        for frame in 0..<90 {
            // A few millimetres of tremor, wandering rather than travelling.
            let jitter = SIMD3<Double>(sin(Double(frame) * 0.7) * 0.003,
                                       cos(Double(frame) * 0.9) * 0.003,
                                       sin(Double(frame) * 1.3) * 0.002)
            XCTAssertNil(latch.promote(hand: start + jitter),
                         "frame \(frame): a still hand read as a grab — this is "
                         + "the tap that stops the pendulum")
        }
        XCTAssertTrue(latch.isPending, "the press should still be waiting")
    }

    /// Right up to the threshold, and not over it.
    func testTheThresholdIsWhereItSaysItIs() {
        var latch = PressLatch<String>()
        latch.press("ball", at: start)
        let justUnder = PressLatch<String>.tapTravel - 1e-6
        XCTAssertNil(latch.promote(hand: start + SIMD3(justUnder, 0, 0)))

        let justOver = PressLatch<String>.tapTravel + 1e-6
        XCTAssertNotNil(latch.promote(hand: start + SIMD3(justOver, 0, 0)))
    }

    // MARK: A drag must act, once

    func testASlowDeliberateDragPromotes() {
        var latch = PressLatch<String>()
        latch.press("bob", at: start)

        // 0.2 m/s at 90 Hz: 2.2 mm a frame, so it takes several frames.
        var promotions = 0
        for frame in 1...45 {
            let hand = start + SIMD3(0.2 * Double(frame) / 90, 0, 0)
            if latch.promote(hand: hand) != nil { promotions += 1 }
        }
        XCTAssertEqual(promotions, 1,
                       "a promotion that fires more than once re-grabs the "
                       + "object on every frame of the carry")
        XCTAssertFalse(latch.isPending)
    }

    /// The sequence the views actually execute: press, promote, press,
    /// promote, with the press first each frame, because a
    /// `targetedToAnyEntity` gesture reports the same entity every frame.
    /// A latch that re-anchored on every press made the bob and the ball
    /// un-grabbable at any speed.
    func testPressingEveryFrameStillPromotes() {
        var latch = PressLatch<String>()

        var promotions = 0
        for frame in 0...45 {
            let hand = start + SIMD3(0.2 * Double(frame) / 90, 0, 0)
            // Exactly the handler's shape: press, then promote, every
            // frame, for as long as nothing has claimed the drag.
            if promotions == 0 { latch.press("bob", at: hand) }
            if latch.promote(hand: hand) != nil { promotions += 1 }
        }

        XCTAssertEqual(promotions, 1,
                       "re-pressing before each promote resets the anchor, so "
                       + "the threshold is never crossed and the object cannot "
                       + "be picked up at all")
    }

    /// The same thing said as a property, so it holds however a caller
    /// interleaves the two calls: a press while one is already pending
    /// must not move the anchor.
    func testASecondPressDoesNotRestartTheFirst() {
        var latch = PressLatch<String>()
        latch.press("first", at: start)
        latch.press("second", at: start + SIMD3(0.5, 0, 0))

        XCTAssertEqual(latch.promote(hand: start + SIMD3(0.02, 0, 0)), "first",
                       "the second press replaced the first — the anchor moves "
                       + "with the hand and the threshold recedes ahead of it")
    }

    /// The pickup must not move the object: the caller pairs the object's
    /// position at the promotion instant with the hand at that instant.
    func testTheDragBuiltAtPromotionDoesNotMoveTheObject() {
        var latch = PressLatch<String>()
        latch.press("ball", at: start)

        let crossing = start + SIMD3(0.05, 0, 0)
        guard let caught = latch.promote(hand: crossing) else {
            return XCTFail("a 50 mm move did not promote")
        }

        // Where the object is at this instant, paired with the hand at
        // this instant — what both call sites now do.
        let objectNow = SIMD3<Double>(1, 2, 3)
        let drag = RelativeDrag(name: caught, target: objectNow, hand: crossing)
        XCTAssertEqual(simd_distance(drag.position(forHand: crossing), objectNow),
                       0, accuracy: 1e-12,
                       "the object moved at the moment it was picked up")

        // And the wrong pairing, spelled out, so the difference is on
        // the record rather than in a comment.
        let backdated = RelativeDrag(name: caught, target: objectNow, hand: start)
        XCTAssertEqual(simd_distance(backdated.position(forHand: crossing), objectNow),
                       0.05, accuracy: 1e-12)
    }

    /// The payload survives the wait — which pendulum, which ball.
    func testThePayloadComesBackWithThePromotion() {
        struct Press: Sendable, Equatable { let id: Int; let name: String }
        var latch = PressLatch<Press>()
        let press = Press(id: 7, name: "ball-7")
        latch.press(press, at: start)
        XCTAssertEqual(latch.promote(hand: start + SIMD3(0, 0.4, 0)), press)
    }

    // MARK: Cancellation

    /// `onEnded` cancels an unpromoted press. A latch that kept it would
    /// promote on the next gesture's first frame, grabbing an object the
    /// user is no longer touching.
    func testACancelledPressCannotPromoteLater() {
        var latch = PressLatch<String>()
        latch.press("bob", at: start)
        latch.cancel()
        XCTAssertFalse(latch.isPending)
        XCTAssertNil(latch.promote(hand: start + SIMD3(1, 0, 0)))
    }

    /// A fresh latch is inert — nothing to promote before anything is
    /// pressed.
    func testAnUntouchedLatchPromotesNothing() {
        var latch = PressLatch<String>()
        XCTAssertFalse(latch.isPending)
        XCTAssertNil(latch.promote(hand: start))
    }

    // MARK: Settling — the tap that acts at gesture end

    /// `settle` resolves a press that never became a drag — what settles is
    /// a tap, and the switch lever's toggle rides it.
    func testSettlingAnUnpromotedPressReturnsThePayload() {
        var latch = PressLatch<String>()
        latch.press("lever", at: start)
        XCTAssertEqual(latch.settle(), "lever")
        XCTAssertFalse(latch.isPending, "settling must clear the press")
        XCTAssertNil(latch.settle(), "a settled press must not settle twice")
    }

    /// A press that promoted was a drag, and a drag must not also act
    /// as a tap at gesture end — that is the double-fire this method
    /// exists to prevent.
    func testSettlingAfterAPromotionReturnsNothing() {
        var latch = PressLatch<String>()
        latch.press("lever", at: start)
        XCTAssertEqual(latch.promote(hand: start + SIMD3(0.05, 0, 0)), "lever")
        XCTAssertNil(latch.settle(),
                     "a promoted press settled as a tap — the drag would "
                     + "also toggle")
    }
}
