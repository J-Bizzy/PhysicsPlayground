//
//  FieldClampTests.swift
//  Physics Playground — app tests
//
//  What survives of the station's clamps, and what must NOT come back.
//
//  The drag walls born in the merged E&M world — `clampToStation` on
//  every `moveCharge`/`movePlate`, plus the escort that exempted a
//  freshly-pulled charge — came out on 2026-08-03 at the owner's
//  direction: this is a room-scale app, and an invisible box that stops
//  a carried charge mid-air reads as broken. These tests pin the new
//  contract from both sides: a hand meets no wall but the floor, and
//  the FREE simulation still cannot run to infinity.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class FieldClampTests: XCTestCase {

    // MARK: A hand meets no walls

    /// Drag a charge three metres out: it must BE three metres out.
    /// This is the assertion that fails if anyone rebuilds the wall.
    func testADraggedChargeGoesExactlyWhereTheHandGoes() {
        let model = FieldModel()
        guard let id = model.charges.first?.id else {
            return XCTFail("a fresh field model should open with charges")
        }
        let far = FieldModel.regionCenter + SIMD3(3.0, 0.4, 2.5)
        model.moveCharge(id: id, to: far)
        XCTAssertEqual(model.charges.first(where: { $0.id == id })?.position,
                       far,
                       "an invisible wall intercepted the hand — the drag "
                       + "walls were removed on 2026-08-03 and must not return")
    }

    /// Same for the capacitor: carry it across the room and it comes.
    /// Only the floor holds (the plates are half a metre tall).
    func testTheCapacitorFollowsTheHandAnywhereAboveTheFloor() {
        let model = FieldModel()
        model.capacitorOn = true
        let far = SIMD3(2.4, 1.1, -2.8)
        model.movePlate(1, toWorld: SIMD3(far.x + model.plateSeparation / 2,
                                          far.y, far.z))
        XCTAssertEqual(model.capacitorCenter.y, far.y, accuracy: 1e-9)
        XCTAssertEqual(model.capacitorCenter.z, far.z, accuracy: 1e-9)

        model.movePlate(1, toWorld: SIMD3(0.2, -2.0, -0.9))
        XCTAssertEqual(model.capacitorCenter.y,
                       FieldModel.plateSize / 2 + 0.15, accuracy: 1e-9,
                       "the plates sank through the floor")
    }

    /// A charge born at a well is born at the fingertips and follows
    /// the hand exactly — the escort mechanism is gone because there
    /// are no walls to be exempt from.
    func testAChargeFromAWellStaysWithTheHand() {
        let model = FieldModel()
        model.removeAllCharges()
        let wellMouth = FieldInstrumentLayout.wellAnchor(index: 0)

        let id = model.addCharge(positive: true, at: wellMouth)
        XCTAssertEqual(model.charges.first(where: { $0.id == id })?.position,
                       wellMouth,
                       "the charge was not born at the fingertips")

        let outward = wellMouth + SIMD3(0.4, 0.1, 0.3)
        model.moveCharge(id: id, to: outward)
        XCTAssertEqual(model.charges.first(where: { $0.id == id })?.position,
                       outward,
                       "the charge was yanked out of the hand that made it")
    }

    // MARK: The free simulation still cannot escape

    /// A mutually repelling pair left to drift for minutes must settle
    /// inside the room-scale safety box — the ONLY bound the module
    /// keeps, and it binds the simulation, never the hand.
    func testFreeChargesNeverLeaveTheSafetyBox() {
        let model = FieldModel()
        // Two positives shove each other apart forever.
        guard let first = model.charges.first?.id else {
            return XCTFail("a fresh field model should open with charges")
        }
        if let negative = model.charges.first(where: { !$0.isPositive }) {
            model.removeCharge(id: negative.id)
        }
        model.addCharge(positive: true,
                        at: FieldModel.regionCenter + SIMD3(0.1, 0, 0))
        _ = first
        model.chargesRespond = true

        for _ in 0..<18_000 { model.stepFreeCharges(dt: 1.0 / 90.0) }   // 200 s

        let box = StationBox(center: FieldModel.regionCenter,
                             halfExtents: FieldModel.safetyHalfExtents)
        for charge in model.charges {
            XCTAssertTrue(box.contains(charge.position),
                          "a free charge drifted out of the safety box "
                          + "to \(charge.position)")
            XCTAssertGreaterThanOrEqual(charge.position.y,
                                        FieldModel.floorClearance - 1e-9)
        }
    }
}
