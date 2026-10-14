//
//  FreeChargeAndFreezeTests.swift
//  PhysicsPlaygroundTests
//
//  The new motion modes, pinned to their physics: freed charges drift
//  the way Coulomb's law says (opposites together, likes apart), a
//  held charge ignores the drift, contact keeps 1/r² finite, the
//  default stays stationary — and frozen magnets genuinely hold still
//  in an arrangement that would otherwise move.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class FreeChargeAndFreezeTests: XCTestCase {

    // MARK: Electric fields — free charges

    /// Two opposite charges, freed: the gap between them closes.
    func testOppositeChargesDriftTogether() {
        let model = FieldModel()
        model.removeAllCharges()
        model.addCharge(positive: true)
        model.addCharge(positive: false)
        let separation = { simd_distance(model.charges[0].position,
                                         model.charges[1].position) }
        let before = separation()

        model.chargesRespond = true
        for _ in 0..<180 { model.stepFreeCharges(dt: 1.0 / 60.0) }
        XCTAssertLessThan(separation(), before - 0.02,
                          "opposites should close the gap")
        // …but never interpenetrate: contact keeps the force finite.
        XCTAssertGreaterThanOrEqual(separation(),
                                    FieldModel.chargeContact - 1e-6,
                                    "contact stops them at touching")
    }

    /// Two like charges, freed: the gap grows.
    func testLikeChargesDriftApart() {
        let model = FieldModel()
        model.removeAllCharges()
        model.addCharge(positive: true)
        model.addCharge(positive: true)
        let separation = { simd_distance(model.charges[0].position,
                                         model.charges[1].position) }
        let before = separation()

        model.chargesRespond = true
        for _ in 0..<180 { model.stepFreeCharges(dt: 1.0 / 60.0) }
        XCTAssertGreaterThan(separation(), before + 0.02,
                             "likes should push apart")
    }

    /// The default is the classic stationary exhibit: nothing moves.
    func testChargesStationaryByDefault() {
        let model = FieldModel()
        model.removeAllCharges()
        model.addCharge(positive: true)
        model.addCharge(positive: false)
        let positions = model.charges.map(\.position)
        for _ in 0..<120 { model.stepFreeCharges(dt: 1.0 / 60.0) }
        for (index, charge) in model.charges.enumerated() {
            XCTAssertEqual(simd_distance(charge.position, positions[index]), 0,
                           "stationary mode must not move charge \(index)")
        }
    }

    /// A charge under the user's hand ignores the drift; its free
    /// partner still rushes toward it.
    func testHeldChargeStaysPutWhileOthersRespond() {
        let model = FieldModel()
        model.removeAllCharges()
        model.addCharge(positive: true)
        model.addCharge(positive: false)
        model.chargesRespond = true
        model.heldChargeID = model.charges[0].id
        let heldBefore = model.charges[0].position
        let freeBefore = model.charges[1].position

        for _ in 0..<120 { model.stepFreeCharges(dt: 1.0 / 60.0) }
        XCTAssertEqual(simd_distance(model.charges[0].position, heldBefore), 0,
                       "the held charge is pinned to the hand")
        XCTAssertGreaterThan(simd_distance(model.charges[1].position, freeBefore),
                             0.01, "its free partner still responds")
    }

    // MARK: Magnetism — freeze

    /// An arrangement that visibly moves when live must hold perfectly
    /// still when dynamics are off — and come alive again when re-enabled.
    func testFrozenMagnetsHoldStill() {
        let model = MagnetismModel()
        // Whatever the opening arrangement is, freeze must hold it.
        model.dynamicsOn = false
        let frozen = model.magnets.map(\.position)
        for _ in 0..<120 { model.step(dt: 1.0 / 60.0) }
        for (index, magnet) in model.magnets.enumerated() {
            XCTAssertLessThan(simd_distance(magnet.position, frozen[index]), 1e-9,
                              "frozen magnet \(index) must not move")
        }

        // Re-enable with a second magnet in play: the pair starts moving again.
        model.dynamicsOn = true
        model.addMagnet()
        let live = model.magnets.map(\.position)
        for _ in 0..<180 { model.step(dt: 1.0 / 60.0) }
        let moved = zip(model.magnets, live)
            .contains { simd_distance($0.position, $1) > 1e-4 }
        XCTAssertTrue(moved, "re-enabled dynamics should move the magnets")
    }
}
