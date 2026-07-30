//
//  CircuitsCoilAnnexTests.swift
//  Physics Playground — app tests
//
//  Circuit Workshop is the app's one wired pair: switch the coil on and
//  the magnetic field stands up beside the bench, cabled to the
//  inductor. Co-presence survives here because the demonstration is
//  WIRING — a cable needs two ends — and nowhere else (DECISIONS.md,
//  2026-07-30). These are the geometric invariants that keep the pair
//  from becoming the overlap the merged worlds died of.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsCoilAnnexTests: XCTestCase {

    private var benchBox: StationBox {
        StationBox(center: CircuitsModel.buildCenter,
                   halfExtents: CircuitsModel.buildHalfExtents)
    }

    private var annexBox: StationBox {
        StationBox(
            center: MagnetismModel.regionCenter
                + SIMD3<Double>(CircuitsSpaceView.coilAnnexOffset),
            halfExtents: MagnetismModel.regionHalfExtents)
    }

    /// The bench and the field it summons may not share space — a
    /// magnet clamped into the bench does not crash, it drifts through
    /// a battery.
    func testTheBenchAndItsAnnexAreDisjoint() {
        XCTAssertTrue(
            benchBox.isSeparated(from: annexBox, margin: 0.05),
            "the coil annex overlaps the bench, or sits closer than "
            + "the 5 cm clearance — gap \(benchBox.separation(from: annexBox)) m")
    }

    /// The whole point of the pair is carrying a magnet the circuit is
    /// driving, so the annex has to be reachable — a step at most.
    func testTheAnnexHasAFaceWithinOneStep() {
        let user = SIMD3<Double>(0, 1.5, 0)
        let (near, _) = annexBox.distanceRange(from: user)
        XCTAssertLessThanOrEqual(
            near, 1.25,
            "the annex is more than a step away — its nearest face is "
            + "\(String(format: "%.2f", near)) m from the user")
    }

    /// The switch is what makes the coil a SOURCE. `electromagnetMoment`
    /// is m = N·I·A for whatever current is stored, on or off — the
    /// gate lives in `electromagnet`, which is nil unless the switch is
    /// on AND the circuit is actually delivering current. Both halves
    /// matter: an off coil with current is dead, and an on coil with no
    /// inductor feeding it is dead too.
    func testTheSwitchAndTheCurrentTogetherMakeTheCoilASource() {
        let magnetism = MagnetismModel()

        magnetism.electromagnetOn = false
        magnetism.setCoilCurrent(0.5)
        XCTAssertNil(magnetism.electromagnet,
                     "a coil that is switched off is not a source")

        magnetism.electromagnetOn = true
        magnetism.setCoilCurrent(0)
        XCTAssertNil(magnetism.electromagnet,
                     "an on coil with nothing feeding it is not a source")

        magnetism.setCoilCurrent(0.5)
        XCTAssertNotNil(magnetism.electromagnet, "a driven coil is")
        XCTAssertEqual(magnetism.electromagnetMoment,
                       400 * 0.5 * .pi * MagnetismModel.coilRadius
                           * MagnetismModel.coilRadius,
                       accuracy: 1e-9,
                       "m = N·I·A, with the current the bench delivered")
    }
}
