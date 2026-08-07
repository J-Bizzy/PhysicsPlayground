//
//  PressLatchTests.swift
//  PhysicsPlaygroundTests
//
//  Two taps that destroyed what they touched, and the shared piece that
//  now stands between them and the model.
//
//  A tap on a swinging pendulum bob — the documented way to open its
//  control ring — stopped the pendulum dead and wiped every trail in the
//  room. A tap on a ball in flight froze it in mid-air, where it hung
//  permanently, having lost its strobe trail and its flight record. Both
//  because one `DragGesture(minimumDistance: 0)` carries every verb in
//  those scenes and fires on a bare press.
//
//  The gesture wiring itself is headset-only — nothing automated can
//  synthesise a pinch, so the two rooms are checked by hand against
//  `docs/ON_DEVICE_TESTS.md`. What IS reachable is the decision the
//  wiring now defers to, and that is where the substance lives:
//
//  · a press that never travels must never promote, at any number of
//    frames — the failure mode is a tap that acts;
//  · a press that travels must promote EXACTLY ONCE — promoting twice
//    would re-grab a held object every frame;
//  · a cancelled press must be unable to promote later, or the NEXT
//    gesture's first frame grabs an object nobody is touching.
//
//  The latch deliberately reports identity and nothing else. The
//  tempting extra — where the object was when the press landed — is
//  wrong twice over, and the reasoning is in `PressLatch`'s header
//  rather than duplicated here.
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
            // A few millimetres of tremor, wandering rather than
            // travelling — the accumulation a naive per-frame sum would
            // wrongly turn into a drag.
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

    /// THE SEQUENCE THE VIEWS ACTUALLY EXECUTE, which is not the one
    /// above, and the difference shipped a total failure.
    ///
    /// A `targetedToAnyEntity` gesture reports the same entity every
    /// frame, and the handler's press branch sits inside `if drag == nil`
    /// — which stays true until a promotion assigns `drag`. So the real
    /// order is press, promote, press, promote, … with the press FIRST
    /// each time. The version above presses once and then only promotes,
    /// which models what the author believed the handler did; it passed
    /// against a latch that re-anchored on every press, and the bob and
    /// the ball were both un-grabbable at any speed.
    ///
    /// This is the same lesson as everything else in this arc: a test
    /// that models the intended call sequence tests the intention.
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

    /// THE PICKUP MUST NOT MOVE THE OBJECT. The caller pairs the
    /// object's position at the promotion instant with the hand at the
    /// promotion instant, and the drag that comes out holds it exactly
    /// still on that frame. This is the whole reason the latch reports
    /// identity and not the object's old position: pairing the OLD
    /// position with the OLD hand replays the 12 mm the hand has already
    /// travelled, and the object catches up in one frame.
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

        // And the WRONG pairing, spelled out, so the difference is on
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
    /// promote on the NEXT gesture's first frame, grabbing an object the
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
}
