//
//  CircuitsCarryDispatchTests.swift
//  PhysicsPlaygroundTests
//
//  ONE DRAG GESTURE, FOUR OWNERS. Circuits routes every frame of its
//  single `DragGesture` to exactly one of: the lead pull, the part
//  carry, the rack, or nobody. `CircuitsSpaceView.carryDispatch` is
//  that decision lifted out of the gesture closure into arithmetic —
//  the same move `resolveGrab` made — because the closure once got the
//  order wrong and nothing headless could see it: the rack outranked a
//  live carry, the rack's `isDragging` stays true for the whole
//  gesture even after its one-shot pull is spent, and so a part pulled
//  from the rack sat frozen at its spawn point until release, when
//  `onEnded` teleported it to the hand.
//

import XCTest
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsCarryDispatchTests: XCTestCase {

    // MARK: The order

    /// THE REGRESSION. On every frame after the spawn frame, the rack
    /// is still dragging AND a carry is live — the carry must win, or
    /// the newborn part freezes at the rack.
    func testASpawnedPartIsCarriedWhileTheRackStillHoldsTheGesture() {
        XCTAssertEqual(
            CircuitsSpaceView.carryDispatch(
                leadPullActive: false, partDragActive: true, rackDragging: true),
            .carry)
    }

    /// A lead in flight outranks everything: wiring is the most
    /// deliberate gesture on the bench, and nothing may steal it.
    func testALeadPullOutranksEverything() {
        XCTAssertEqual(
            CircuitsSpaceView.carryDispatch(
                leadPullActive: true, partDragActive: true, rackDragging: true),
            .leadPull)
        XCTAssertEqual(
            CircuitsSpaceView.carryDispatch(
                leadPullActive: true, partDragActive: false, rackDragging: false),
            .leadPull)
    }

    /// The rack owns a frame only when nothing else is live — which is
    /// every browsing frame, and the one frame a pull commits on
    /// (the carry does not exist yet on that frame, so this is what
    /// lets the spawn happen at all).
    func testTheRackOnlyOwnsAFrameWhenNothingIsCarried() {
        XCTAssertEqual(
            CircuitsSpaceView.carryDispatch(
                leadPullActive: false, partDragActive: false, rackDragging: true),
            .rack)
        XCTAssertEqual(
            CircuitsSpaceView.carryDispatch(
                leadPullActive: false, partDragActive: false, rackDragging: false),
            .idle)
    }

    // MARK: The trap that makes the order load-bearing

    /// After a pull is classified and spent, the rack keeps reporting
    /// `isDragging` until the gesture ends, and `updateDrag` returns
    /// nil forever. This is BY DESIGN (the slot must come back exactly
    /// once) — but it is why a dispatch that consults the rack before
    /// the carry starves the carry. If this behaviour ever changes,
    /// the dispatch order above deserves a fresh look.
    func testASpentPullLeavesTheRackStillDragging() throws {
        let specs = (0..<12).map { index in
            Well.Spec(name: "slot\(index)", tint: .white, label: "Slot \(index)",
                      preview: {
                          ModelEntity(mesh: .generateSphere(radius: 0.015))
                      },
                      position: CircuitsPartsLayout.rightSlot(index: index),
                      spawn: { _ in UUID() })
        }
        let well = Well(specs)
        well.visibleCount = 6
        well.update(dt: 1 / 90)

        let slot = try XCTUnwrap(well.source(at: 2))
        XCTAssertTrue(well.beginDrag(slot, hand: .zero))
        // Travel off the rack's axis until the gesture classifies PULL
        // and the slot comes back — once.
        var pulled: Int?
        for step in 1...20 {
            if let index = well.updateDrag(hand: [0, 0, Float(step) * 0.01]) {
                pulled = index
                break
            }
        }
        XCTAssertEqual(pulled, 2, "the pull never resolved")

        // The spent state: nil forever, but still dragging.
        for step in 21...30 {
            XCTAssertNil(well.updateDrag(hand: [0, 0, Float(step) * 0.01]),
                         "a spent pull must never return the slot again")
        }
        XCTAssertTrue(well.isDragging,
                      "the rack holds the gesture until it ends — the fact "
                      + "that makes the carry-before-rack order load-bearing")
        well.endDrag()
        XCTAssertFalse(well.isDragging)
    }
}
