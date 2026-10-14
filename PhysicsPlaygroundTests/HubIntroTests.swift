//
//  HubIntroTests.swift
//  Physics Playground — app tests
//
//  The arrival choreography, held as pure math. The one assertion
//  nothing else could hold: the calibration sound's bell is baked into
//  a WAV at a fixed second, and the wordmark's landing must sit exactly
//  on it.
//

import XCTest
@testable import PhysicsPlayground

final class HubIntroTests: XCTestCase {

    /// The cross-pin: neither file imports the other's reasoning, and this
    /// test is the only thing keeping them one clock.
    func testTheBellStrikesExactlyAtTheLanding() {
        XCTAssertEqual(HubIntro.landingTime, SoundPalette.calibrationLanding,
                       accuracy: 1e-9,
                       "the bell and the landing have drifted apart — "
                       + "retune one to the other")
    }

    /// The opening frame: the title is present (mid-fade) and alone —
    /// every other curve still reads zero.
    func testTheTitleOpensAlone() {
        let early = 0.4
        XCTAssertGreaterThan(HubIntro.titleOpacity(at: early), 0.2)
        XCTAssertEqual(HubIntro.titleBlend(at: early), 0,
                       "the mark must hold its centred pose through the beat")
        XCTAssertEqual(HubIntro.stageOpacity(at: early), 0)
        XCTAssertEqual(HubIntro.exhibitOpacity(slot: 0, at: early), 0)
        XCTAssertEqual(HubIntro.signOpacity(at: early), 0)
    }

    /// The beat is a minimum: at any instant before it the mark has not
    /// begun to move, however fast the gallery actually built.
    func testTheBeatHolds() {
        for t in stride(from: 0.0, to: HubIntro.minimumBeat, by: 0.1) {
            XCTAssertEqual(HubIntro.titleBlend(at: t), 0,
                           "the flight started early, at \(t)s")
        }
        XCTAssertEqual(HubIntro.titleBlend(at: HubIntro.landingTime), 1)
    }

    /// The flight is monotone — the mark travels toward the wall and
    /// never doubles back.
    func testTheFlightIsMonotone() {
        var last: Float = -1
        for t in stride(from: HubIntro.minimumBeat - 0.1,
                        through: HubIntro.landingTime + 0.1, by: 0.02) {
            let blend = HubIntro.titleBlend(at: t)
            XCTAssertGreaterThanOrEqual(blend, last)
            last = blend
        }
    }

    /// The cascade's order is the design: stage first, then the
    /// miniatures in slot order, the signs last.
    func testTheCascadeArrivesInOrder() {
        func start(of curve: (Double) -> Float) -> Double {
            var t = 0.0
            while curve(t) <= 0, t < 10 { t += 0.005 }
            return t
        }
        let stage = start { HubIntro.stageOpacity(at: $0) }
        let first = start { HubIntro.exhibitOpacity(slot: 0, at: $0) }
        let last = start { HubIntro.exhibitOpacity(slot: 5, at: $0) }
        let signs = start { HubIntro.signOpacity(at: $0) }
        XCTAssertLessThan(stage, first, "the stage should rise first")
        XCTAssertLessThan(first, last, "the miniatures should wave, not pop")
        XCTAssertLessThan(last, signs, "the door signs arrive last")
    }

    /// And the cascade rises to meet the landing mark rather than
    /// waiting for it — the stage is already coming up when the bell
    /// strikes.
    func testTheRoomRisesToMeetTheMark() {
        XCTAssertGreaterThan(HubIntro.stageOpacity(at: HubIntro.landingTime), 0.3)
    }

    /// Everything lands at exactly 1 — the scene removes its intro
    /// components at `isFinished`, and a curve that never reached 1
    /// would visibly snap there when it did.
    func testEveryCurveLandsAtOne() {
        let count = 6
        var t = 0.0
        while !HubIntro.isFinished(at: t, exhibitCount: count) { t += 0.01 }

        XCTAssertEqual(HubIntro.titleOpacity(at: t), 1)
        XCTAssertEqual(HubIntro.titleBlend(at: t), 1)
        XCTAssertEqual(HubIntro.stageOpacity(at: t), 1)
        XCTAssertEqual(HubIntro.signOpacity(at: t), 1)
        for slot in 0..<count {
            XCTAssertEqual(HubIntro.exhibitOpacity(slot: slot, at: t), 1)
            XCTAssertEqual(HubIntro.exhibitScale(slot: slot, at: t), 1)
        }
        // And a hair earlier it was not finished — the flag is the
        // moment the last curve lands, not a lazy timeout.
        XCTAssertFalse(HubIntro.isFinished(at: t - 0.05, exhibitCount: count))
    }

    /// The pop: a miniature arrives slightly small and lands at full
    /// size, riding its own opacity.
    func testTheExhibitPopRidesItsFade() {
        XCTAssertEqual(HubIntro.exhibitScale(slot: 2, at: 0), 0.88)
        let landed = HubIntro.cascadeStart + 0.12 + 2 * HubIntro.exhibitStagger
            + HubIntro.exhibitFade
        XCTAssertEqual(HubIntro.exhibitScale(slot: 2, at: landed), 1,
                       accuracy: 1e-6)
    }
}
