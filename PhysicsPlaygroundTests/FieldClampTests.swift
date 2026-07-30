//
//  FieldClampTests.swift
//  Physics Playground — app tests
//
//  Electric Fields' region clamps, asserted as containment. These
//  invariants were born in the merged E&M world's layout tests — the
//  world died of geometry, but the clamps it forced into existence are
//  fixes regardless of layout: before them, `moveCharge` and
//  `moveGaussSurface` clamped only `y`, so a charge could be dragged
//  clear across the room. A limit nothing is near is a limit nobody
//  tested; these keep the limits tested now that they exist.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class FieldClampTests: XCTestCase {

    /// The region every clamp answers to, in the model's own frame.
    private var region: StationBox {
        StationBox(center: FieldModel.regionCenter,
                   halfExtents: FieldModel.regionHalfExtents)
    }

    /// The capacitor is up to a metre wide at full separation, and its
    /// clamp is inset by its own half-size — so even wide open, shoved
    /// hard at a wall, the plates stay inside.
    func testTheWidestCapacitorStaysInsideTheRegion() {
        let model = FieldModel()
        model.plateSeparation = FieldModel.plateSeparationRange.upperBound
        model.movePlate(1, toWorld: SIMD3(50, 1.35, -0.9))
        let half = SIMD3(model.plateSeparation / 2,
                         FieldModel.plateSize / 2, FieldModel.plateSize / 2)
        XCTAssertTrue(
            region.contains(StationBox(center: model.capacitorCenter,
                                       halfExtents: half), tolerance: 1e-6),
            "the capacitor at full separation escapes the region")
    }

    /// Same for the flux meter, a 1.1 m sphere at full radius.
    func testTheWidestGaussSurfaceStaysInsideTheRegion() {
        let model = FieldModel()
        model.gaussSurfaceRadius = FieldModel.gaussRadiusRange.upperBound
        model.moveGaussSurface(to: SIMD3(-50, 1.35, -0.9))
        XCTAssertTrue(
            region.contains(
                StationBox(center: model.gaussSurfaceCenter,
                           halfExtents: SIMD3(repeating: model.gaussSurfaceRadius)),
                tolerance: 1e-6),
            "the Gauss surface at full radius escapes the region")
    }

    /// And a dragged charge, which is what a user actually does —
    /// inset by its contact radius, so the SPHERE stays inside rather
    /// than merely its centre.
    func testADraggedChargeCannotLeaveTheRegion() {
        let model = FieldModel()
        guard let id = model.charges.first?.id else {
            return XCTFail("a fresh field model should open with charges")
        }
        model.moveCharge(id: id, to: SIMD3(-50, 90, 50))
        guard let moved = model.charges.first(where: { $0.id == id }) else {
            return XCTFail("the charge vanished")
        }
        XCTAssertTrue(
            region.contains(
                StationBox(center: moved.position,
                           halfExtents: SIMD3(repeating: FieldModel.chargeContact)),
                tolerance: 1e-6),
            "a charge dragged at the room escapes the region")
    }
}
