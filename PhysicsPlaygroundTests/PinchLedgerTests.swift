//
//  PinchLedgerTests.swift
//  PhysicsPlaygroundTests
//
//  The same-object rule: two hands closing on the same object together
//  mean resize; one object in each hand, a hand on nothing, or a hand
//  joining late mean something else. `PinchLedger` is the half a test can
//  reach — the hands' reports, recorded by hand here.
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

    // MARK: When two hands are a resize (2026-11-02)

    func testNoPinchesOrOneDecideNothing() {
        let ledger = PinchLedger()
        XCTAssertEqual(ledger.verdict(now: 0), .undecided)
        ledger.record("left", active: true, on: object(named: "magnet-a").collider, now: 0)
        XCTAssertEqual(ledger.verdict(now: 0.05), .undecided,
                       "one hand alone was judged before the other's pinch could arrive")
    }

    func testBothHandsClosingTogetherOnOneObjectResize() {
        let magnet = object(named: "magnet-a")
        let ledger = PinchLedger()
        ledger.record("left", active: true, on: magnet.collider, now: 10)
        ledger.record("right", active: true, on: magnet.owner, now: 10.25)
        XCTAssertEqual(ledger.verdict(now: 10.3), .resize)
    }

    func testOneObjectInEachHandIsNotAResize() {
        let ledger = PinchLedger()
        ledger.record("left", active: true, on: object(named: "magnet-a").collider, now: 0)
        ledger.record("right", active: true, on: object(named: "magnet-b").collider, now: 0.1)
        XCTAssertEqual(ledger.verdict(now: 0.15), .refuse,
                       "two grabs scaled the lab")
    }

    func testAHandThatClosesOnNothingIsNotAResize() {
        let ledger = PinchLedger()
        ledger.record("left", active: true, on: object(named: "magnet-a").collider, now: 0)
        ledger.record("right", active: true, on: nil, now: 0.1)
        XCTAssertEqual(ledger.verdict(now: 0.15), .refuse,
                       "a second pinch that missed scaled the lab — the defect "
                       + "the owner reported on 2026-11-02")
    }

    func testASecondHandJoiningLateIsNotAResize() {
        let magnet = object(named: "magnet-a")
        let ledger = PinchLedger()
        ledger.record("left", active: true, on: magnet.collider, now: 0)
        for t in stride(from: 0.1, through: 1.2, by: 0.1) {
            ledger.record("left", active: true, on: magnet.collider, now: t)
        }
        ledger.record("right", active: true, on: magnet.collider, now: 1.2)
        XCTAssertEqual(ledger.verdict(now: 1.25), .refuse,
                       "a hand joining one already carrying the object resized it")
    }

    func testTheWindowIsWhatItSays() {
        let magnet = object(named: "magnet-a")
        let ledger = PinchLedger()
        ledger.record("left", active: true, on: magnet.collider, now: 0)
        ledger.record("right", active: true, on: magnet.collider,
                      now: PinchLedger.togetherWithin)
        XCTAssertEqual(ledger.verdict(now: PinchLedger.togetherWithin), .resize)

        let late = PinchLedger()
        late.record("left", active: true, on: magnet.collider, now: 0)
        late.record("right", active: true, on: magnet.collider,
                    now: PinchLedger.togetherWithin + 0.05)
        XCTAssertEqual(late.verdict(now: PinchLedger.togetherWithin + 0.05), .refuse)
    }

    func testAResizeThatHasBegunRunsToItsEnd() {
        let magnet = object(named: "magnet-a")
        let ledger = PinchLedger()
        ledger.record("left", active: true, on: magnet.collider, now: 0)
        ledger.record("right", active: true, on: magnet.collider, now: 0.1)
        XCTAssertEqual(ledger.decide(now: 0.1), .resize)
        // Both hands held so still that neither reports for a second: the
        // pinches expire, and the resize must not drop out from under them.
        XCTAssertEqual(ledger.decide(now: 1.2), .resize)
        ledger.gestureEnded()
        XCTAssertEqual(ledger.decide(now: 1.2), .undecided)
    }

    func testARefusalHoldsWhenOneHandLetsGo() {
        let ledger = PinchLedger()
        ledger.record("left", active: true, on: object(named: "magnet-a").collider, now: 0)
        ledger.record("right", active: true, on: object(named: "magnet-b").collider, now: 0.1)
        XCTAssertEqual(ledger.decide(now: 0.1), .refuse)
        ledger.record("left", active: false, on: nil, now: 0.5)
        XCTAssertEqual(ledger.decide(now: 0.5), .refuse,
                       "a refused gesture started resizing halfway through")
    }

    func testACarryingHandKeepsTheMomentItClosed() {
        // A hand still carrying when the gesture ends must not look as
        // though it had just closed, or a quick second pinch reads as
        // "together".
        let magnet = object(named: "magnet-a")
        let ledger = PinchLedger()
        ledger.record("left", active: true, on: magnet.collider, now: 0)
        for t in stride(from: 0.1, through: 1.0, by: 0.1) {
            ledger.record("left", active: true, on: magnet.collider, now: t)
        }
        ledger.record("right", active: true, on: magnet.collider, now: 1.0)
        XCTAssertEqual(ledger.decide(now: 1.0), .refuse)
        ledger.record("right", active: false, on: nil, now: 1.1)
        ledger.gestureEnded()
        ledger.record("left", active: true, on: magnet.collider, now: 1.15)
        ledger.record("right", active: true, on: magnet.collider, now: 1.2)
        XCTAssertEqual(ledger.decide(now: 1.2), .refuse)
    }

    func testAPinchBelongsToWhatItLandedOn() {
        let a = object(named: "magnet-a")
        let ledger = PinchLedger()
        ledger.record("left", active: true, on: a.collider, now: 0)
        ledger.record("right", active: true, on: a.collider, now: 0.1)
        // Later reports of the same pinch name something else (the hand has
        // moved over a neighbour): the pinch is still on what it closed on.
        ledger.record("right", active: true, on: object(named: "magnet-b").collider, now: 0.2)
        XCTAssertEqual(ledger.verdict(now: 0.2), .resize)
    }
}
