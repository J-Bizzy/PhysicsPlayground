//
//  DialDragTests.swift
//  PhysicsPlaygroundTests
//
//  `SpatialDial` is the instrument the interaction law leans on — the
//  machined gauge you reach out and twist, which is what replaces a
//  slider without reintroducing a gaze-revealed control (DECISIONS.md,
//  2026-07-29). It shipped untested and unadopted. Its twist arithmetic
//  was deliberately split out as a pure struct so it could be tested
//  without a scene; this is that test, written before anything is built
//  on it.
//
//  The case that matters most is the wrap: hand angle comes from atan2,
//  which rolls over from +π to −π. Read naively, one frame of that
//  rollover is a 2π jump — the needle slams from one end of the range to
//  the other while the user's hand moves a millimetre.
//

import XCTest
import RenderKit

final class DialDragTests: XCTestCase {

    /// `turnsForFullSweep: 0.75` means three-quarters of a turn covers the
    /// whole range — the gauge-like default a real instrument uses.
    func testThreeQuarterTurnCoversTheWholeRange() {
        var dial = DialDrag(name: "d", startValue: 0, startAngle: 0,
                            range: 0...100, turnsForFullSweep: 0.75)
        // 0.75 turn = 1.5π radians, fed in steps small enough not to wrap.
        let total = 1.5 * Double.pi
        for step in 1...30 {
            dial.advance(toAngle: total * Double(step) / 30)
        }
        XCTAssertEqual(dial.value, 100, accuracy: 1e-9)
    }

    func testHalfOfAFullSweepIsHalfTheRange() {
        var dial = DialDrag(name: "d", startValue: 0, startAngle: 0,
                            range: 0...100, turnsForFullSweep: 0.75)
        let half = 0.75 * Double.pi
        for step in 1...30 {
            dial.advance(toAngle: half * Double(step) / 30)
        }
        XCTAssertEqual(dial.value, 50, accuracy: 1e-9)
    }

    /// Turning the other way lowers the value.
    func testTwistingBackwardsLowersTheValue() {
        var dial = DialDrag(name: "d", startValue: 50, startAngle: 0,
                            range: 0...100, turnsForFullSweep: 0.75)
        for step in 1...15 {
            dial.advance(toAngle: -0.75 * Double.pi * Double(step) / 15)
        }
        XCTAssertEqual(dial.value, 0, accuracy: 1e-9)
    }

    /// THE bug this math exists to prevent. atan2 rolls +π → −π; the frame
    /// delta must be read as the short way round (+0.28 rad), not as a
    /// near-full turn backwards.
    func testAtan2RolloverIsTheShortWayRound() {
        var dial = DialDrag(name: "d", startValue: 50, startAngle: 3.0,
                            range: 0...100, turnsForFullSweep: 0.75)
        dial.advance(toAngle: -3.0)
        // Short way is +2π − 6.0 ≈ +0.2832 rad, i.e. a small increase.
        let valuePerRadian = 100.0 / (2 * Double.pi * 0.75)
        let expected = 50 + (2 * Double.pi - 6.0) * valuePerRadian
        XCTAssertEqual(dial.value, expected, accuracy: 1e-9)
        XCTAssertGreaterThan(dial.value, 50, "a rollover must not run the dial backwards")
        // Read naively the delta would be −6 rad: −127 units, clamping the
        // dial to 0. The short way is worth ~6 units, so anything past a
        // tenth of the range means the unwrap didn't happen.
        XCTAssertLessThan(dial.value, 60, "nor jump it most of a turn")
    }

    /// Symmetric: rolling the other way across the seam is a small decrease.
    func testRolloverInTheOtherDirection() {
        var dial = DialDrag(name: "d", startValue: 50, startAngle: -3.0,
                            range: 0...100, turnsForFullSweep: 0.75)
        dial.advance(toAngle: 3.0)
        let valuePerRadian = 100.0 / (2 * Double.pi * 0.75)
        let expected = 50 - (2 * Double.pi - 6.0) * valuePerRadian
        XCTAssertEqual(dial.value, expected, accuracy: 1e-9)
        XCTAssertLessThan(dial.value, 50)
        XCTAssertGreaterThan(dial.value, 40, "a rollover is a nudge, not a sweep")
    }

    /// The value accumulates across the whole gesture, so a dial with a
    /// wide range can be wound round more than once.
    func testValueAccumulatesAcrossMultipleTurns() {
        var dial = DialDrag(name: "d", startValue: 0, startAngle: 0,
                            range: 0...1000, turnsForFullSweep: 0.25)
        // Two full turns, in steps that never exceed π.
        for step in 1...40 {
            dial.advance(toAngle: 4 * Double.pi * Double(step) / 40)
        }
        XCTAssertEqual(dial.value, 1000, accuracy: 1e-9, "clamped at the top")
    }

    func testValueClampsAtBothEnds() {
        var high = DialDrag(name: "d", startValue: 90, startAngle: 0,
                            range: 0...100, turnsForFullSweep: 0.75)
        for step in 1...30 { high.advance(toAngle: 3 * Double.pi * Double(step) / 30) }
        XCTAssertEqual(high.value, 100, accuracy: 1e-12)

        var low = DialDrag(name: "d", startValue: 10, startAngle: 0,
                           range: 0...100, turnsForFullSweep: 0.75)
        for step in 1...30 { low.advance(toAngle: -3 * Double.pi * Double(step) / 30) }
        XCTAssertEqual(low.value, 0, accuracy: 1e-12)
    }

    /// A caller passing a start value outside the range gets a legal dial,
    /// not an out-of-range one that only becomes legal after a twist.
    func testStartValueIsClampedIntoRange() {
        XCTAssertEqual(
            DialDrag(name: "d", startValue: 999, startAngle: 0, range: 0...100).value, 100)
        XCTAssertEqual(
            DialDrag(name: "d", startValue: -999, startAngle: 0, range: 0...100).value, 0)
    }

    /// No twist, no change — a tap on a dial must not nudge it.
    func testNoMotionLeavesTheValueAlone() {
        var dial = DialDrag(name: "d", startValue: 42, startAngle: 1.234,
                            range: 0...100, turnsForFullSweep: 0.75)
        dial.advance(toAngle: 1.234)
        XCTAssertEqual(dial.value, 42, accuracy: 1e-12)
    }

    /// Ranges that don't start at zero (a real dial: 0.5 kg … 3 kg) map
    /// proportionally rather than treating the lower bound as an origin.
    func testOffsetRangeMapsProportionally() {
        var dial = DialDrag(name: "mass", startValue: 0.5, startAngle: 0,
                            range: 0.5...3.0, turnsForFullSweep: 0.75)
        let half = 0.75 * Double.pi
        for step in 1...30 { dial.advance(toAngle: half * Double(step) / 30) }
        XCTAssertEqual(dial.value, 1.75, accuracy: 1e-9, "half a sweep is mid-range")
    }

    func testNameIsCarriedThroughForHitTesting() {
        XCTAssertEqual(
            DialDrag(name: "wind-speed", startValue: 0, startAngle: 0, range: 0...1).name,
            "wind-speed")
    }
}
