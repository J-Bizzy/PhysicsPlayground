//
//  FieldGrabResolutionTests.swift
//  PhysicsPlaygroundTests
//
//  The pinch-to-charge resolver: an entity named with a charge's UUID
//  wins outright, and an anonymous hit (the invisible two-hand scale
//  plate spans the whole field region) falls back to the nearest charge
//  within reach of the hand — so a pinch ON a charge always grabs it,
//  never silently does nothing.
//

import XCTest
import simd
@testable import PhysicsPlayground

@MainActor
final class FieldGrabResolutionTests: XCTestCase {

    private let near = UUID()
    private let far = UUID()

    private var charges: [(id: UUID, position: SIMD3<Double>)] {
        [(near, SIMD3(0, 1, -1)), (far, SIMD3(0.5, 1, -1))]
    }

    func testUUIDNameResolvesThatCharge() {
        // Even with the hand right on top of the OTHER charge: an
        // explicit name is the user's actual target.
        let id = EMChargeStation.resolveCharge(
            names: ["some-child", far.uuidString],
            hand: SIMD3(0, 1, -1),
            charges: charges)
        XCTAssertEqual(id, far)
    }

    func testAnonymousHitNearAChargeFallsBackToIt() {
        // The scale-handle scenario: no name matches, but the hand is
        // 5 cm from a charge — that is the charge being grabbed.
        let id = EMChargeStation.resolveCharge(
            names: ["scale-handle"],
            hand: SIMD3(0.05, 1, -1),
            charges: charges)
        XCTAssertEqual(id, near)
    }

    func testFallbackPicksTheNearestCharge() {
        let id = EMChargeStation.resolveCharge(
            names: [""],
            hand: SIMD3(0.4, 1, -1),
            charges: charges)
        XCTAssertEqual(id, far)
    }

    func testFarHandResolvesNothing() {
        // 30 cm from every charge: a pinch on empty space must not
        // yank a distant charge into the hand.
        let id = EMChargeStation.resolveCharge(
            names: ["scale-handle"],
            hand: SIMD3(0, 1, -0.7),
            charges: charges)
        XCTAssertNil(id)
    }

    func testUnknownUUIDNameStillFallsBackByProximity() {
        // A stale name (charge deleted mid-gesture) is not a match,
        // but the hand may still be on a live charge.
        let id = EMChargeStation.resolveCharge(
            names: [UUID().uuidString],
            hand: SIMD3(0.02, 1, -1),
            charges: charges)
        XCTAssertEqual(id, near)
    }

    func testMagnitudeSetterClampsToRange() {
        // Accuracy: the value round-trips through coulombs (×1e-6,
        // ×1e6), which costs an ulp.
        let model = FieldModel()
        model.selectedMagnitudeMicroCoulombs = 999
        XCTAssertEqual(model.selectedMagnitudeMicroCoulombs,
                       FieldModel.magnitudeRange.upperBound, accuracy: 1e-9)
        model.selectedMagnitudeMicroCoulombs = 0
        XCTAssertEqual(model.selectedMagnitudeMicroCoulombs,
                       FieldModel.magnitudeRange.lowerBound, accuracy: 1e-9)
    }
}
