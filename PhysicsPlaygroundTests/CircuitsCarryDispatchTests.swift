//
//  CircuitsCarryDispatchTests.swift
//  PhysicsPlaygroundTests
//
//  One drag gesture, four owners: `CircuitsSpaceView.carryDispatch`
//  routes each frame to the lead pull, the part carry, the shelf, or
//  nobody. Lifted out of the gesture closure because the closure once
//  let the shelf outrank a live carry, freezing a newborn part at it.
//

import XCTest
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsCarryDispatchTests: XCTestCase {

    // MARK: The order

    /// The regression. On every frame after the spawn frame, the rack
    /// is still dragging and a carry is live — the carry must win, or
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

    // MARK: The shelf never holds a pull

    /// A drag that starts on a slot is the view's pull, not the shelf's:
    /// the shelf refuses it outright, so a newborn part can never be left
    /// frozen at a rack that thinks it is still browsing. Only the crown
    /// holds a gesture, and it holds it until the hand lets go.
    func testASlotDragNeverEntersTheShelfAndTheCrownHoldsItsGesture() throws {
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
        XCTAssertFalse(well.beginDrag(slot, hand: .zero), "the shelf claimed a slot drag")
        XCTAssertFalse(well.isDragging)
        XCTAssertEqual(well.sourceIndex(of: slot), 2, "the view pulls from this slot")

        let crown = try XCTUnwrap(well.crown)
        XCTAssertTrue(well.beginDrag(crown, hand: .zero))
        for step in 1...10 {
            well.updateDrag(hand: [0, Float(step) * 0.01, 0])
        }
        XCTAssertTrue(well.isDragging,
                      "the crown holds the gesture until it ends — the rack frame")
        well.endDrag()
        XCTAssertFalse(well.isDragging)
    }
}
