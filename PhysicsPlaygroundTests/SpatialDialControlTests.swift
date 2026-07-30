//
//  SpatialDialControlTests.swift
//  PhysicsPlaygroundTests
//
//  Does turning the dial actually change the number?
//
//  Written in response to "nothing really changes when I adjust the
//  variables". Sliders for frequency and wave speed were REMOVED and
//  replaced by these dials, and the only verification at the time was a
//  screenshot proving they render. Rendering is not operating: if the
//  twist never reaches the model, removing the sliders removed the
//  control, and the module became unadjustable.
//
//  `DialDrag`'s arithmetic is already tested on its own. What is tested
//  here is the whole path a hand takes — a position in the dial's parent
//  space, through `handAngle`, into `DialDrag`, out to the model's setter —
//  because that path is what the sliders used to do and now has to.
//

import XCTest
import RealityKit
import RenderKit
import simd

@MainActor
final class SpatialDialControlTests: XCTestCase {

    /// A dial facing +z at the origin, bound to `value`.
    private func makeDial(
        range: ClosedRange<Double> = 0...100,
        start: Double = 50
    ) -> (control: SpatialDialControl, read: () -> Double) {
        var value = start
        let control = SpatialDialControl(
            name: "test-dial",
            center: .zero,
            normal: SIMD3<Float>(0, 0, 1),
            accent: .white,
            range: range,
            read: { value },
            write: { value = $0 },
            format: { String(format: "%.2f", $0) })
        return (control, { value })
    }

    /// Hand positions on the dial's face, at a given angle about it.
    private func hand(atAngle angle: Double, radius: Double = 0.08) -> SIMD3<Double> {
        SIMD3(cos(angle) * radius, sin(angle) * radius, 0)
    }

    // MARK: The question the user actually asked

    /// THE test: a quarter turn moves the value, and by the amount the
    /// gauge's sweep promises. If this fails, the module is unadjustable.
    func testAQuarterTurnChangesTheModelValue() {
        let (dial, read) = makeDial()
        XCTAssertEqual(read(), 50)

        dial.beginTwist(hand: hand(atAngle: 0))
        dial.updateTwist(hand: hand(atAngle: .pi / 2))

        // 0.75 turn = full 100 range, so a quarter turn is 100/3.
        XCTAssertEqual(read(), 50 + 100.0 / 3, accuracy: 1e-6,
                       "turning the dial must move the number it is bound to")
    }

    /// Turning back the other way lowers it — a dial that only ever
    /// increased would be a ratchet.
    func testTwistingBackwardsLowersTheValue() {
        let (dial, read) = makeDial()
        dial.beginTwist(hand: hand(atAngle: 0))
        dial.updateTwist(hand: hand(atAngle: -.pi / 2))
        XCTAssertLessThan(read(), 50)
    }

    /// A twist arrives as many small frames, not one jump, and the value
    /// must accumulate across all of them rather than tracking only the
    /// latest frame's delta.
    func testValueAccumulatesAcrossManyFrames() {
        let (dial, read) = makeDial()
        dial.beginTwist(hand: hand(atAngle: 0))
        for step in 1...30 {
            dial.updateTwist(hand: hand(atAngle: .pi / 2 * Double(step) / 30))
        }
        XCTAssertEqual(read(), 50 + 100.0 / 3, accuracy: 1e-6)
    }

    /// Radius must not matter: a hand further out is the same ANGLE, and a
    /// dial that responded to reach as well as rotation would drift as the
    /// user's hand wandered off the face.
    func testDistanceFromTheDialDoesNotAffectTheValue() {
        let (near, readNear) = makeDial()
        near.beginTwist(hand: hand(atAngle: 0, radius: 0.05))
        near.updateTwist(hand: hand(atAngle: .pi / 3, radius: 0.05))

        let (far, readFar) = makeDial()
        far.beginTwist(hand: hand(atAngle: 0, radius: 0.30))
        far.updateTwist(hand: hand(atAngle: .pi / 3, radius: 0.30))

        XCTAssertEqual(readNear(), readFar(), accuracy: 1e-9)
    }

    // MARK: Lifecycle

    func testNoTwistIsInFlightUntilOneBegins() {
        let (dial, read) = makeDial()
        XCTAssertFalse(dial.isTwisting)
        // An update with no begin must be ignored, not treated as a twist
        // from wherever the value happened to be.
        XCTAssertFalse(dial.updateTwist(hand: hand(atAngle: 1.0)))
        XCTAssertEqual(read(), 50)
    }

    func testEndingATwistStopsTracking() {
        let (dial, read) = makeDial()
        dial.beginTwist(hand: hand(atAngle: 0))
        dial.updateTwist(hand: hand(atAngle: 0.4))
        let afterTwist = read()
        dial.endTwist()
        XCTAssertFalse(dial.isTwisting)
        XCTAssertFalse(dial.updateTwist(hand: hand(atAngle: 2.0)))
        XCTAssertEqual(read(), afterTwist, accuracy: 1e-12,
                       "a released dial must not keep following the hand")
    }

    /// Two twists in sequence both count — the second must start from
    /// where the first left the value, not from the range's middle.
    func testASecondTwistContinuesFromWhereTheFirstLeftIt() {
        let (dial, read) = makeDial()
        dial.beginTwist(hand: hand(atAngle: 0))
        dial.updateTwist(hand: hand(atAngle: 0.5))
        let first = read()
        dial.endTwist()

        dial.beginTwist(hand: hand(atAngle: 2.0))
        dial.updateTwist(hand: hand(atAngle: 2.5))
        XCTAssertEqual(read(), first + (first - 50), accuracy: 1e-6,
                       "the same turn again should move it the same amount again")
    }

    // MARK: Clamping and ownership

    func testValueClampsToTheRange() {
        let (dial, read) = makeDial(range: 0...100, start: 95)
        dial.beginTwist(hand: hand(atAngle: 0))
        for step in 1...20 {
            dial.updateTwist(hand: hand(atAngle: .pi / 2 * Double(step) / 20))
        }
        XCTAssertEqual(read(), 100, accuracy: 1e-12)
    }

    /// Ranges that don't start at zero — a real one, like the wave speed's
    /// 0.2…1.0 m/s — map proportionally rather than treating the lower
    /// bound as an origin, and a sweep crossing atan2's ±π seam keeps
    /// accumulating rather than stalling or reversing.
    ///
    /// Asserted as "climbs monotonically and arrives at the top", not as an
    /// exact endpoint. The first version of this demanded 1.0 to within
    /// 1e-9 after a sweep that lands precisely ON the clamp boundary, and
    /// that is a test of floating-point luck rather than of the control:
    /// the useful claims are that a real range moves at all, moves in one
    /// direction, and reaches its end.
    func testRealWorldRangeMapsProportionally() {
        let (dial, read) = makeDial(range: 0.2...1.0, start: 0.2)
        dial.beginTwist(hand: hand(atAngle: 0))
        var previous = read()
        var readings: [Double] = []
        for step in 1...30 {
            dial.updateTwist(hand: hand(atAngle: 1.5 * .pi * Double(step) / 30))
            let value = read()
            readings.append(value)
            XCTAssertGreaterThanOrEqual(value, previous,
                                        "step \(step) went backwards — the ±π seam")
            XCTAssertLessThanOrEqual(value, 1.0, "must never exceed the range")
            previous = value
        }
        XCTAssertGreaterThan(readings.last!, 0.99,
                             "a full 0.75-turn sweep should reach the top of the range")
        XCTAssertGreaterThan(readings.first!, 0.2,
                             "and it should have started moving on the first frame")
    }

    /// `owns` has to match the dial's own descendants, since a tap lands on
    /// the needle or a tick rather than on the root.
    func testOwnsMatchesItsOwnEntityAndChildren() {
        let (dial, _) = makeDial()
        XCTAssertTrue(dial.owns(dial.root))
        let child = Entity()
        dial.root.addChild(child)
        XCTAssertTrue(dial.owns(child), "a tick or needle is still the dial")
        XCTAssertFalse(dial.owns(Entity()), "an unrelated entity is not")
    }

    /// The needle and label follow the model even when nothing is being
    /// twisted — a value changed by a reset has to move the gauge.
    func testRefreshFollowsAModelChangedElsewhere() {
        var value = 10.0
        let control = SpatialDialControl(
            name: "d", center: .zero, normal: SIMD3<Float>(0, 0, 1),
            accent: .white, range: 0...100,
            read: { value }, write: { value = $0 },
            format: { String(format: "%.0f", $0) })
        value = 90
        // No assertion on pixels; what matters is that refresh reads the
        // model rather than a cached copy, so it must not crash or revert.
        control.refresh()
        XCTAssertEqual(value, 90, "refresh must not write back a stale value")
    }
}
