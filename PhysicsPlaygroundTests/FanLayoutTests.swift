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
//  THIS FILE LET A DEVICE-ONLY FAILURE SHIP, on 2026-08-07, and the
//  three reasons are worth naming because each is a way a test can look
//  thorough and cover nothing:
//
//  1. IT MEASURED THE WRONG THING. `testNeighboursAreSeparatedAtFullOpen`
//     cleared 0.052 m — the disc's painted FACE. Hit-testing uses the
//     COLLIDER, which is 0.068 m across. Every gap between 0.052 and
//     0.068 read as fine here and was unaimable in the room.
//  2. IT ONLY EVER TESTED `FanLayout()`. Not one of the layouts a module
//     actually ships was ever passed through it, and the default is the
//     only layout in the app that nobody uses. Gravity Lab's clock bank
//     carried a 50° span hand-tuned for four discs while its array grew
//     to six; the arithmetic was fine, and no test looked at it.
//  3. ITS CEILING OF NINE WAS SILENT. Nine is not arbitrary — it is
//     exactly where the default arc runs out of room, which is why
//     Gravity Lab's ten-world fan carries a bespoke layout. But the test
//     said only `for count in 2...9`, so the wall was a magic number
//     with no explanation and nothing to hit if a tenth choice were
//     added to a picker using the default. It is derived and named
//     below now.
//
//  So `testEveryShippedFanClearsItsColliders` is the load-bearing test
//  here now: it walks the layouts the app really builds, at the counts
//  it really builds them with, against the collider width the picker
//  really uses. The generic tests below still earn their place — they
//  cover the degenerate counts a module can reach by deleting content —
//  but they are no longer the whole story.
//

import XCTest
import simd
import RenderKit
@testable import PhysicsPlayground

final class FanLayoutTests: XCTestCase {

    // MARK: The criterion — what the modules actually build

    /// Every fan the app ships, at the count it ships it with.
    ///
    /// Named here rather than reached through the views because a
    /// `SpatialPicker` lives in a `@State` inside a `View`; this is the
    /// same arithmetic the view hands it, and the pairing is what
    /// `testEveryShippedFanClearsItsColliders` is checking. If a module
    /// gains a picker, add it — and note that the two DERIVED entries
    /// cannot go wrong when their content grows, which is the whole
    /// argument for `FanLayout.spread`.
    @MainActor
    private var shippedFans: [(name: String, count: Int, layout: FanLayout)] {
        [
            ("GravityLab clock speed",
             GravityLabModel.timeScales.count,
             FanLayout.spread(count: GravityLabModel.timeScales.count,
                              itemSpan: Double(SpatialPicker.colliderSpan),
                              reach: 0.34, verticalScale: 0.25,
                              lift: 0, stagger: 0)),
            ("GravityLab worlds",
             GravityLabModel.Preset.allCases.count,
             FanLayout(span: 120 * .pi / 180, reach: 0.58,
                       verticalScale: 0.22, lift: 0, stagger: 0)),
            ("Projectiles worlds",
             KinematicsModel.gravityPresets.count,
             FanLayout(span: 54 * .pi / 180, reach: 0.32,
                       verticalScale: 0.25, lift: 0, stagger: 0)),
        ]
    }

    /// A fan whose discs are closer together than a disc's touch target
    /// is wide cannot be aimed at, however tidily it reads.
    @MainActor
    func testEveryShippedFanClearsItsColliders() {
        let target = Double(SpatialPicker.colliderSpan)
        for fan in shippedFans {
            let spacing = fan.layout.minimumAdjacentSpacing(count: fan.count)
            XCTAssertGreaterThan(
                spacing, target,
                String(format: "%@ puts %d discs %.4f m apart against a %.3f m "
                       + "touch target — adjacent discs cannot be told apart "
                       + "by a pinch.", fan.name, fan.count, spacing, target))
        }
    }

    /// …and must still be reachable. A fan wide enough to clear its own
    /// colliders is no use if it opens across the room.
    @MainActor
    func testEveryShippedFanStaysWithinReach() {
        for fan in shippedFans {
            for index in 0..<fan.count {
                let offset = fan.layout.placement(index: index, count: fan.count,
                                                  openness: 1).offset
                XCTAssertLessThan(simd_length(offset), 0.70,
                                  "\(fan.name) item \(index) opens out of reach")
                XCTAssertGreaterThanOrEqual(offset.y, 0,
                                            "\(fan.name) item \(index) opens downward")
            }
        }
    }

    // MARK: The derivation

    /// `spread` must fit any count it is handed, not just the ones we
    /// happen to ship — that is the point of deriving it. The failure it
    /// exists to prevent is a content array growing past a hand-typed
    /// span.
    func testSpreadFitsEveryCountFromTwoToTwentyFour() {
        let itemSpan = 0.068
        for count in 2...24 {
            let layout = FanLayout.spread(count: count, itemSpan: itemSpan,
                                          reach: 0.34, verticalScale: 0.25,
                                          lift: 0, stagger: 0)
            XCTAssertGreaterThan(
                layout.minimumAdjacentSpacing(count: count), itemSpan,
                "spread(count: \(count)) still overlaps")
        }
    }

    /// It must also be TIGHT. A derivation that answers every question
    /// with the widest legal fan has not derived anything.
    func testSpreadStaysAsNarrowAsTheCountAllows() {
        let itemSpan = 0.068
        let four = FanLayout.spread(count: 4, itemSpan: itemSpan, reach: 0.34,
                                    verticalScale: 0.25, lift: 0, stagger: 0)
        let eight = FanLayout.spread(count: 8, itemSpan: itemSpan, reach: 0.34,
                                     verticalScale: 0.25, lift: 0, stagger: 0)
        XCTAssertLessThan(four.span, eight.span,
                          "fewer discs must not ask for a wider arc")
        XCTAssertLessThan(four.span, 150 * .pi / 180,
                          "four discs do not need the whole default arc")
    }

    /// Past the widest legal arc there is nowhere to go but outward, and
    /// it must actually go there rather than quietly overlapping.
    func testSpreadReachesOutwardWhenTheArcRunsOut() {
        let itemSpan = 0.12
        let crowded = FanLayout.spread(count: 20, itemSpan: itemSpan, reach: 0.30,
                                       verticalScale: 0.25, lift: 0, stagger: 0)
        XCTAssertGreaterThan(crowded.reach, 0.30,
                             "the arc was maxed out and the reach did not grow")
        XCTAssertGreaterThan(crowded.minimumAdjacentSpacing(count: 20), itemSpan)
    }

    func testSpreadIsFiniteForDegenerateCounts() {
        for count in [0, 1] {
            let layout = FanLayout.spread(count: count, itemSpan: 0.068, reach: 0.3)
            XCTAssertTrue(layout.span.isFinite && layout.reach.isFinite)
            let placement = layout.placement(index: 0, count: count, openness: 1)
            XCTAssertTrue(placement.offset.x.isFinite && placement.offset.y.isFinite)
        }
    }

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
    ///
    /// MEASURED AGAINST THE COLLIDER, not the painted face. This test
    /// cleared 0.052 m — the disc's visual diameter — until 2026-08-07,
    /// and a pinch does not land on paint.
    ///
    /// The default 150° / 0.27 m arc holds NINE discs and no more. The
    /// capacity is derived here rather than written in as a loop bound,
    /// because the number is a real property of the geometry and the
    /// reason Gravity Lab's ten-world fan carries a bespoke layout — and
    /// because a bound with no explanation is indistinguishable from
    /// somebody having stopped counting.
    @MainActor
    func testTheDefaultArcHoldsNineDiscsAndSaysSo() {
        let fan = FanLayout()
        let target = Double(SpatialPicker.colliderSpan)

        let capacity = (2...40).last { count in
            (2...count).allSatisfy {
                fan.minimumAdjacentSpacing(count: $0) > target
            }
        } ?? 0

        XCTAssertEqual(
            capacity, 9,
            "The default arc now holds \(capacity) discs, not 9. That is not "
            + "automatically wrong — but Gravity Lab's ten-world fan exists "
            + "BECAUSE the answer was 9, so if this has moved, check whether "
            + "that layout is still needed and whether anything else was tuned "
            + "around the old number.")

        // …and the next one along is where it fails, which is the whole
        // job of `spread`.
        XCTAssertLessThan(fan.minimumAdjacentSpacing(count: capacity + 1), target)
        let spread = FanLayout.spread(count: capacity + 1, itemSpan: target,
                                      reach: fan.reach,
                                      verticalScale: fan.verticalScale,
                                      lift: fan.lift, stagger: fan.stagger)
        XCTAssertGreaterThan(spread.minimumAdjacentSpacing(count: capacity + 1), target,
                             "past the default's capacity, `spread` must cope")
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
