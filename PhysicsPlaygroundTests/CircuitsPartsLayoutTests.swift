//
//  CircuitsPartsLayoutTests.swift
//  Physics Playground — app tests
//
//  The parts palette's placement, which is the one thing about it a Mac
//  can check. Whether it LOOKS right needs a headset; whether a wearer
//  can reach it, and whether it stands clear of the bench and of the
//  furniture row beneath it, is arithmetic.
//
//  This file exists because the tray it replaced had no test of any
//  kind, and its two placement bugs were both found by eye — once by
//  arithmetic in a code comment, once by a screenshot showing the motor
//  standing on the words "AC Source". Circuit Workshop is the last module
//  to get a layout it can be held to; `FieldInstrumentLayout` and its
//  tests are the pattern.
//

import XCTest
import simd
@testable import PhysicsPlayground

final class CircuitsPartsLayoutTests: XCTestCase {

    // THESE TESTS DESCRIBED TWO FLANKS UNTIL 2026-08-08, and the layout
    // has changed twice since — first to a right-hand block, then to a
    // single scrolling column of six with the multimeter as a twelfth
    // slot. The mirror, third-column and per-flank-overflow checks went
    // with the arrangement they described.
    //
    // THE TWO THAT SURVIVED ARE THE TWO THAT MATTERED, and letting them
    // lapse cost exactly what they were written to prevent. The new
    // column shipped at z −0.55, which is 55.5° off axis against this
    // module's own 48° limit — the SAME trade the deleted comment
    // warned about in these words: the first palette "passed the reach
    // test above with 3 cm to spare and still put half its labels off
    // the edge of the screen, because it bought that reach by pulling
    // the columns forward in z — which spends angle to buy distance."
    //
    // A test that describes an arrangement dies with the arrangement. A
    // test that describes a CONSTRAINT should have been carried across
    // and was not.

    /// Only the six on screen are checked, and that is the point: the
    /// rack slides so the window always occupies the top six positions,
    /// so a twelfth slot never sits anywhere a sixth one does not.
    private func windowSlots() -> [(Int, SIMD3<Float>)] {
        (0..<CircuitsPartsLayout.rightVisibleRows).map {
            ($0, CircuitsPartsLayout.rightSlot(index: $0))
        }
    }

    // MARK: Reachable, and visible

    /// YOUR ARM GETS THERE.
    func testEveryVisibleSlotIsWithinReach() {
        for (index, slot) in windowSlots() {
            XCTAssertLessThanOrEqual(
                CircuitsPartsLayout.reach(to: slot),
                CircuitsPartsLayout.maximumReach,
                """
                slot \(index) at \(slot) is \(CircuitsPartsLayout.reach(to: slot)) m \
                away — a step, not a reach.
                """)
        }
    }

    /// AND YOUR EYES DO, which is the binding constraint here and the
    /// one that was let lapse. Reach is bought by pulling the column
    /// forward; forward is paid for in angle.
    func testEveryVisibleSlotIsInsideTheFrame() {
        for (index, slot) in windowSlots() {
            let angle = CircuitsPartsLayout.offAxisAngle(to: slot)
            XCTAssertLessThanOrEqual(
                angle, CircuitsPartsLayout.maximumOffAxisAngle,
                """
                slot \(index) at \(slot) is \(angle)° off axis, out at the edge \
                of vision. If this was bought to satisfy the reach check, the \
                column has been pulled too far forward — that is the trade \
                this pair of tests exists to keep honest.
                """)
        }
    }

    /// The two limits are satisfied with room to spare, not scraped.
    ///
    /// A layout sitting exactly on a limit is one that the next change
    /// breaks, and both of these have been scraped before: the reach
    /// check once passed by 3 cm while the labels were off screen.
    func testTheWindowClearsBothLimitsWithMargin() {
        let worstReach = windowSlots().map {
            CircuitsPartsLayout.reach(to: $0.1)
        }.max() ?? 0
        let worstAngle = windowSlots().map {
            CircuitsPartsLayout.offAxisAngle(to: $0.1)
        }.max() ?? 0
        XCTAssertLessThan(worstReach, CircuitsPartsLayout.maximumReach - 0.02,
                          "the window is scraping the reach limit at \(worstReach)")
        XCTAssertLessThan(worstAngle,
                          CircuitsPartsLayout.maximumOffAxisAngle - 1.0,
                          "the window is scraping the angle limit at \(worstAngle)°")
    }

    // MARK: Coverage and shape

    /// EVERY component kind stands somewhere. The failure this guards is
    /// silent and total: a kind in no list has no source in the room, so
    /// it is a part the bench can hold and nobody can make.
    func testEveryComponentKindHasASlot() {
        let listed = CircuitsPartsLayout.Flank.allCases
            .flatMap { CircuitsPartsLayout.kinds(on: $0) }
        for kind in CircuitsModel.ComponentKind.allCases {
            XCTAssertTrue(listed.contains(kind),
                          "\(kind) can be built but not made — no slot lists it")
        }
        XCTAssertEqual(Set(listed).count, listed.count,
                       "a kind is listed twice, so it gets two slots")
    }

    /// No two slots coincide.
    func testNoTwoSlotsCoincide() {
        let all = (0..<12).map { CircuitsPartsLayout.rightSlot(index: $0) }
        for i in all.indices {
            for j in (i + 1)..<all.count {
                XCTAssertGreaterThan(simd_distance(all[i], all[j]), 0.02,
                                     "slots \(i) and \(j) are on top of each other")
            }
        }
    }

    /// The column reads downward, in the authored order.
    func testTheColumnReadsDownward() {
        let all = (0..<12).map { CircuitsPartsLayout.rightSlot(index: $0) }
        for i in 1..<all.count {
            XCTAssertLessThan(all[i].y, all[i - 1].y,
                              "slot \(i) is not below slot \(i - 1)")
            XCTAssertEqual(all[i].x, all[0].x, accuracy: 1e-6,
                           "slot \(i) left the column")
        }
    }

    // MARK: The rack against the build volume

    /// EVERY SLOT CLEARS THE BUILD VOLUME BY THE MARGIN.
    ///
    /// The audit (P1-28) said this file "checks reach, angle, mirroring
    /// and pitch — never a slot against the clamp box", and it was right:
    /// the rack sat 0.10 m from a volume that ends at 0.70, inside the
    /// 0.12 m `stationMargin`, and nothing said so. The consequence it
    /// noticed — parts jumping inward at birth — is a symptom, and the
    /// symptom is legitimate (the rack is furniture, the volume is where
    /// circuits live, and the rule keeps them apart). The violation was
    /// the gap.
    func testEveryRackSlotClearsTheBuildVolume() {
        let clamp = Float(CircuitsModel.buildHalfExtents.x)
        let margin = Float(InstrumentClearance.stationMargin)
        for index in 0..<CircuitsPartsLayout.rightVisibleRows {
            let slot = CircuitsPartsLayout.rightSlot(index: index)
            XCTAssertGreaterThanOrEqual(abs(slot.x) - clamp, margin - 1e-4, """
                rack slot \(index) is at x \(slot.x), only \
                \(abs(slot.x) - clamp) m outside a build volume that ends at \
                \(clamp). The margin is \(margin) — the rack is standing in \
                the space the clearance rule reserves.
                """)
        }
    }

    /// …AND STILL WITHIN REACH AND ON AXIS. Pushing the rack out to clear
    /// the volume is the obvious repair and it spends the other two
    /// budgets; this is the one that says how much is left.
    func testTheRackStaysReachableAndOnAxis() {
        let viewer = SIMD3<Float>(InstrumentClearance.viewer)
        for index in 0..<CircuitsPartsLayout.rightVisibleRows {
            let slot = CircuitsPartsLayout.rightSlot(index: index)
            let reach = simd_length(slot - viewer)
            XCTAssertLessThanOrEqual(Double(reach),
                                     InstrumentClearance.maximumReach, """
                rack slot \(index) is \(reach) m away — past the reach limit, \
                so you step toward your own parts.
                """)
            let angle = atan2(abs(slot.x), abs(slot.z)) * 180 / .pi
            XCTAssertLessThanOrEqual(angle, 48.0, """
                rack slot \(index) is \(angle) degrees off the forward axis, \
                out at the edge of vision. Bring `rightZ` toward the wearer \
                before pushing `rightColumnX` any further out.
                """)
        }
    }

    /// The pair can fail. Without this they are two budgets that happen
    /// to be satisfied by whatever numbers are in the file.
    func testTheClearanceRuleWouldCatchTheOldColumn() {
        let clamp = Float(CircuitsModel.buildHalfExtents.x)
        let margin = Float(InstrumentClearance.stationMargin)
        // 0.80, where the column stood until 2026-08-09.
        XCTAssertLessThan(0.80 - clamp, margin, """
            0.80 satisfies the margin, so the assertion above is not \
            measuring the thing that was wrong.
            """)
    }
}
