//
//  PinchLedgerTests.swift
//  PhysicsPlaygroundTests
//
//  The same-object rule (owner, 2026-08-03): two hands pinching the
//  SAME object mean resize; one object in each hand means two grabs,
//  and the scale rig must stay out of it. `PinchLedger` is the half of
//  that rule a test can reach — the counting of distinct owners. The
//  gesture interplay itself is headset-only and lives on the on-device
//  script.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class PinchLedgerTests: XCTestCase {

    /// A named object with an anonymous child collider, the shape every
    /// grabbable in the app takes: the pinch lands on the child, the
    /// owner is the named ancestor.
    private func object(named name: String) -> (owner: Entity, collider: Entity) {
        let owner = Entity()
        owner.name = name
        let collider = Entity()
        owner.addChild(collider)
        return (owner, collider)
    }

    func testAPinchResolvesToItsNamedAncestor() {
        let magnet = object(named: "magnet-a")
        XCTAssertTrue(PinchLedger.owner(of: magnet.collider) === magnet.owner,
                      "the pinch did not walk up to the named object")
        XCTAssertTrue(PinchLedger.owner(of: magnet.owner) === magnet.owner)
    }

    func testTwoPartsOfOneObjectCountAsOne() {
        let magnet = object(named: "magnet-a")
        let secondPart = Entity()
        magnet.owner.addChild(secondPart)

        let count = PinchLedger.distinctOwnerCount(
            of: [PinchLedger.owner(of: magnet.collider),
                 PinchLedger.owner(of: secondPart)])
        XCTAssertEqual(count, 1,
                       "two pinches on one object read as two objects — "
                       + "same-object resize would be suppressed")
    }

    func testTwoDifferentObjectsCountAsTwo() {
        let a = object(named: "magnet-a")
        let b = object(named: "magnet-b")
        let count = PinchLedger.distinctOwnerCount(
            of: [PinchLedger.owner(of: a.collider),
                 PinchLedger.owner(of: b.collider)])
        XCTAssertEqual(count, 2,
                       "one object in each hand read as one — the accidental "
                       + "resize this rule exists to stop would still fire")
    }

    func testAnObjectAndItsOwnAncestorCountAsOne() {
        let a = object(named: "magnet-a")
        let count = PinchLedger.distinctOwnerCount(
            of: [a.owner, PinchLedger.owner(of: a.collider)])
        XCTAssertEqual(count, 1)
    }

    func testAnEmptyLedgerAllowsScale() {
        XCTAssertTrue(PinchLedger().allowsScale,
                      "no pinches at all must not suppress the rig")
    }
}
