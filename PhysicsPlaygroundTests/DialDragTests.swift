//
//  DialDragTests.swift
//  PhysicsPlaygroundTests
//
//  The twist math behind the Spatial Dial: a value accumulates from
//  the signed change in hand angle, wrap-safe across the atan2 seam
//  and clamped to range — so a three-quarter turn sweeps the whole
//  range and a full spin never makes the needle jump backward.
//

import RenderKit
import XCTest

final class DialDragTests: XCTestCase {

    /// A three-quarter turn (the default sweep) moves the value across
    /// its entire range, exactly.
    func testFullSweepCoversTheRange() {
        var drag = DialDrag(name: "d", startValue: 0, startAngle: 0,
                            range: 0...10, turnsForFullSweep: 0.75)
        // Advance through the seam in small steps to 0.75 of a turn.
        let target = 2 * Double.pi * 0.75
        let steps = 40
        for i in 1...steps {
            drag.advance(toAngle: target * Double(i) / Double(steps))
        }
        XCTAssertEqual(drag.value, 10, accuracy: 1e-9)
    }

    /// Crossing the +π/−π seam adds a small step, never subtracts a
    /// whole turn.
    func testWrapAcrossTheSeamIsContinuous() {
        var drag = DialDrag(name: "d", startValue: 5, startAngle: 3.0,
                            range: 0...10, turnsForFullSweep: 1)
        // 3.0 → 3.2 rad, but expressed past the seam as −3.08 (= 3.20 − 2π).
        let value = drag.advance(toAngle: 3.2 - 2 * .pi)
        let expected = 5 + 0.2 * (10.0 / (2 * .pi))
        XCTAssertEqual(value, expected, accuracy: 1e-9, "a +0.2 rad nudge, not −2π")
    }

    /// The value clamps at both ends and stays there.
    func testClampsAtEnds() {
        var drag = DialDrag(name: "d", startValue: 9.5, startAngle: 0,
                            range: 0...10, turnsForFullSweep: 0.5)
        drag.advance(toAngle: .pi)          // +half range = +5 → clamps at 10
        XCTAssertEqual(drag.value, 10, accuracy: 1e-12)
        drag.advance(toAngle: 1.5 * .pi)    // keep turning past the stop
        XCTAssertEqual(drag.value, 10, accuracy: 1e-12)
    }

    /// Reversing the twist reverses the value.
    func testReversible() {
        var drag = DialDrag(name: "d", startValue: 5, startAngle: 0,
                            range: 0...10, turnsForFullSweep: 1)
        drag.advance(toAngle: 1.0)
        let up = drag.value
        drag.advance(toAngle: 0.0)
        XCTAssertEqual(drag.value, 5, accuracy: 1e-9)
        XCTAssertGreaterThan(up, 5)
    }
}
