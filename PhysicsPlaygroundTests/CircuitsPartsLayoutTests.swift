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

    /// The tallest part in the module, for worst-case pitch. The wire is
    /// a 0.12 m cylinder and the battery 0.11; anything taller arriving
    /// later makes this test fail rather than silently push the top row
    /// out of reach.
    private static let tallestPart: Float = 0.12

    private func slots() -> [(CircuitsPartsLayout.Flank, Int, SIMD3<Float>)] {
        var out: [(CircuitsPartsLayout.Flank, Int, SIMD3<Float>)] = []
        let pitch = CircuitsPartsLayout.rowPitch(tallestPart: Self.tallestPart)
        for flank in CircuitsPartsLayout.Flank.allCases {
            for index in CircuitsPartsLayout.kinds(on: flank).indices {
                out.append((flank, index,
                            CircuitsPartsLayout.slot(flank, index: index,
                                                     rowPitch: pitch)))
            }
        }
        return out
    }

    // MARK: Coverage

    /// EVERY component kind stands somewhere.
    ///
    /// The failure this guards is silent and total: a kind nobody
    /// assigned to a flank has no source in the room, so it is a part
    /// the bench can hold but nobody can make.
    func testEveryComponentKindIsOnExactlyOneFlank() {
        let placed = CircuitsPartsLayout.Flank.allCases
            .flatMap { CircuitsPartsLayout.kinds(on: $0) }

        XCTAssertEqual(Set(placed).count, placed.count,
                       "a part kind stands on both flanks")
        XCTAssertEqual(Set(placed), Set(CircuitsModel.ComponentKind.allCases),
                       "a part kind has no source in the room — add it to "
                       + "CircuitsPartsLayout.kinds(on:)")
    }

    /// No flank holds more than the block can show.
    func testNeitherFlankOverflowsItsBlock() {
        let capacity = CircuitsPartsLayout.rows * CircuitsPartsLayout.columns
        for flank in CircuitsPartsLayout.Flank.allCases {
            XCTAssertLessThanOrEqual(
                CircuitsPartsLayout.kinds(on: flank).count, capacity,
                "\(flank) has more parts than its \(capacity) slots — the "
                + "extras would stack below the block, into the furniture")
        }
    }

    // MARK: Reach

    /// EVERY slot is reachable. The invariant the two-column shape was
    /// chosen for: a third column lands past this line.
    func testEverySlotIsWithinReach() {
        for (flank, index, slot) in slots() {
            XCTAssertLessThanOrEqual(
                CircuitsPartsLayout.reach(to: slot),
                CircuitsPartsLayout.maximumReach,
                "\(flank) slot \(index) at \(slot) is a step away, not a reach")
        }
    }

    /// EVERY slot is inside the frame.
    ///
    /// THE CONSTRAINT THAT ACTUALLY BIT. The first build of this palette
    /// passed the reach test above with 3 cm to spare and still put half
    /// its labels off the edge of the screen, because it bought that
    /// reach by pulling the columns forward in z — which spends angle to
    /// buy distance. Reach says "your arm gets there"; this says "your
    /// eyes do".
    func testEverySlotIsInsideTheFrame() {
        for (flank, index, slot) in slots() {
            XCTAssertLessThanOrEqual(
                CircuitsPartsLayout.offAxisAngle(to: slot),
                CircuitsPartsLayout.maximumOffAxisAngle,
                "\(flank) slot \(index) at \(slot) is "
                + "\(CircuitsPartsLayout.offAxisAngle(to: slot))° off axis, "
                + "out at the edge of vision")
        }
    }

    /// A third column would breach one limit or the other — the test
    /// that keeps the "why only two columns" comment honest. If this
    /// ever fails, the geometry changed and the palette can grow.
    func testAThirdColumnWouldNotFit() {
        let pitch = CircuitsPartsLayout.rowPitch(tallestPart: Self.tallestPart)
        let gap = CircuitsPartsLayout.outerColumnX - CircuitsPartsLayout.innerColumnX
        let thirdColumn = SIMD3<Float>(
            CircuitsPartsLayout.outerColumnX + gap,
            CircuitsPartsLayout.bottomRowY
                + Float(CircuitsPartsLayout.rows - 1) * pitch,
            CircuitsPartsLayout.columnZ)

        let breachesReach = CircuitsPartsLayout.reach(to: thirdColumn)
            > CircuitsPartsLayout.maximumReach
        let breachesFrame = CircuitsPartsLayout.offAxisAngle(to: thirdColumn)
            > CircuitsPartsLayout.maximumOffAxisAngle
        XCTAssertTrue(breachesReach || breachesFrame,
                      "a third column now fits — the comment in "
                      + "CircuitsPartsLayout saying it cannot is stale")
    }

    // MARK: Clearance from the furniture row

    /// The lowest nameplate clears the layer bank below it.
    ///
    /// The bench's furniture reads as a row at one height — Clear plate,
    /// meter, bench, layers — and the palette is a second storey above
    /// it. The tallest thing in that row is the layer bank: five plates
    /// on a 0.066 pitch, centred at benchPivot.y − 0.06, so its top plate
    /// reaches about 1.36. A block hanging into that would put a part
    /// name across a switch.
    func testTheLowestNameplateClearsTheFurnitureRow() {
        let bankCentre = CircuitsRenderer.benchPivot.y - 0.06
        let bankTop = bankCentre + Float(5 - 1) / 2 * 0.066 + 0.025
        // A `Well` hangs its plate 0.034 under the object's own bottom.
        let lowestPlate = CircuitsPartsLayout.bottomRowY
            - Self.tallestPart / 2 - 0.034

        XCTAssertGreaterThan(
            lowestPlate - bankTop, 0.02,
            "the palette's bottom row hangs into the furniture row "
            + "(plate at \(lowestPlate), bank tops out at \(bankTop))")
    }

    // MARK: Shape

    /// No two parts share a slot.
    func testNoTwoSlotsCoincide() {
        let positions = slots().map(\.2)
        for (i, a) in positions.enumerated() {
            for (j, b) in positions.enumerated() where j > i {
                XCTAssertGreaterThan(simd_distance(a, b), 0.05,
                                     "slots \(i) and \(j) are on top of each other")
            }
        }
    }

    /// The two BLOCKS mirror each other, so the room is not lopsided.
    ///
    /// Per ROW, not per index — slot 0 is the outer column on the left
    /// and the inner column on the right, because both flanks read left
    /// to right (see `slot`). Comparing index to index instead is the
    /// obvious version of this test and it fails against correct
    /// geometry; it is written down here so the next person does not
    /// "fix" the layout to satisfy it.
    func testTheBlocksMirror() {
        let pitch = CircuitsPartsLayout.rowPitch(tallestPart: Self.tallestPart)
        for row in 0..<CircuitsPartsLayout.rows {
            let first = row * CircuitsPartsLayout.columns
            let indices = first..<(first + CircuitsPartsLayout.columns)
            let left = indices.map {
                CircuitsPartsLayout.slot(.left, index: $0, rowPitch: pitch)
            }
            let right = indices.map {
                CircuitsPartsLayout.slot(.right, index: $0, rowPitch: pitch)
            }
            XCTAssertEqual(left.map { abs($0.x) }.sorted(),
                           right.map { abs($0.x) }.sorted(),
                           "row \(row) stands off-centre")
            XCTAssertEqual(Set(left.map(\.y)), Set(right.map(\.y)),
                           "row \(row) sits at a different height per side")
            XCTAssertEqual(Set(left.map(\.z)), Set(right.map(\.z)))
        }
    }

    /// Reading order runs left to right and top to bottom, on both
    /// sides. The mirrored column ordering is the easiest thing here to
    /// get backwards, and backwards means the labels read right to left
    /// on one flank only.
    func testBothFlanksReadLeftToRight() {
        let pitch = CircuitsPartsLayout.rowPitch(tallestPart: Self.tallestPart)
        for flank in CircuitsPartsLayout.Flank.allCases {
            let first = CircuitsPartsLayout.slot(flank, index: 0, rowPitch: pitch)
            let second = CircuitsPartsLayout.slot(flank, index: 1, rowPitch: pitch)
            XCTAssertLessThan(first.x, second.x,
                              "\(flank) reads right to left")
            XCTAssertEqual(first.y, second.y, accuracy: 1e-6,
                           "\(flank)'s first two parts are not on one row")
        }
        let top = CircuitsPartsLayout.slot(.left, index: 0, rowPitch: pitch)
        let next = CircuitsPartsLayout.slot(.left, index: 2, rowPitch: pitch)
        XCTAssertLessThan(next.y, top.y, "the block reads bottom to top")
    }
}
