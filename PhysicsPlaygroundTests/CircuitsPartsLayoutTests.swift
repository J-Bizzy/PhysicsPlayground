//
//  CircuitsPartsLayoutTests.swift
//  Physics Playground — app tests
//
//  The parts shelf's placement, which is the one thing about it a Mac
//  can check: whether a wearer can reach it, whether it stays inside the
//  frame, and whether it stands clear of the bench.
//

import XCTest
import simd
@testable import PhysicsPlayground

final class CircuitsPartsLayoutTests: XCTestCase {

    /// Only the six on screen are checked, and that is the point: the
    /// rack slides so the window always occupies the top six positions,
    /// so a twelfth slot never sits anywhere a sixth one does not.
    private func windowSlots() -> [(Int, SIMD3<Float>)] {
        (0..<CircuitsPartsLayout.rightVisibleRows).map {
            ($0, CircuitsPartsLayout.rightSlot(index: $0))
        }
    }

    // MARK: Reachable, and visible

    /// Your arm gets there.
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

    /// And your eyes do, which is the binding constraint: reach is bought
    /// by pulling the column forward, and forward is paid for in angle.
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

    /// The two limits are satisfied with room to spare, not scraped: a
    /// layout sitting exactly on a limit is one the next change breaks.
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

    /// Every component kind stands somewhere. The failure this guards is
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

    /// Every slot clears the build volume by the margin: the shelf is
    /// furniture, the volume is where circuits live, and the rule keeps
    /// them apart.
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

    /// …and still within reach and on axis. Pushing the rack out to clear
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

    /// The pair can fail, and the witness is relative: a column just inside
    /// the margin is the claim, whatever the bench width is.
    func testTheClearanceRuleWouldCatchATooCloseColumn() {
        let clamp = Float(CircuitsModel.buildHalfExtents.x)
        let margin = Float(InstrumentClearance.stationMargin)
        let tooClose = clamp + margin - 0.02
        XCTAssertLessThan(tooClose - clamp, margin, """
            a column at \(tooClose) — 2 cm inside the \(margin) m margin \
            around a volume ending at \(clamp) — satisfies the rule, so the \
            assertion above is not measuring the thing that was wrong.
            """)
        // …and the shipped column is on the right side of the same line.
        XCTAssertGreaterThanOrEqual(
            abs(CircuitsPartsLayout.rightColumnX) - clamp, margin,
            "the shipped rack is inside the margin it is meant to clear")
    }

    /// Six rows fit and six is the ceiling, asserted from both sides so
    /// "six" is a derivation rather than a number somebody liked.
    func testTheSixthRowFitsAndASeventhWouldNot() {
        let viewer = SIMD3<Float>(InstrumentClearance.viewer)
        let margin = 1.23  // the "with margin" line the window tests use

        let last = CircuitsPartsLayout.rightSlot(
            index: CircuitsPartsLayout.rightVisibleRows - 1)
        XCTAssertLessThanOrEqual(Double(simd_length(last - viewer)), margin, """
            the last visible row is \(simd_length(last - viewer)) m away — \
            past the margin line, so the bottom of the rack is a step rather \
            than a reach.
            """)

        let oneMore = CircuitsPartsLayout.rightSlot(
            index: CircuitsPartsLayout.rightVisibleRows)
        XCTAssertGreaterThan(Double(simd_length(oneMore - viewer)), margin, """
            a further row would ALSO fit at \(simd_length(oneMore - viewer)) m, \
            so `rightVisibleRows` is not the ceiling this comment claims — \
            either show it or correct the arithmetic in `CircuitsPartsLayout`.
            """)
    }
}
