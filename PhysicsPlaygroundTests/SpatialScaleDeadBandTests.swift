//
//  SpatialScaleDeadBandTests.swift
//  PhysicsPlaygroundTests
//
//  The hands' resize waits out a dead band (2026-11-02): a held pinch
//  wobbles by a few per cent, and the rig used to follow every bit of it.
//  Nothing moves until the hands have spread or closed by
//  `scaleDeadBand` or turned by `turnDeadBand`, and then the view moves
//  from where it stood, with no jump by the band it waited out.
//

import XCTest
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class SpatialScaleDeadBandTests: XCTestCase {

    private func rig() -> SpatialScaleRig {
        SpatialScaleRig(pivot: [0, 1.3, -1], range: 0.35...4.0)
    }

    func testAWobbleInsideTheBandMovesNothing() {
        let rig = rig()
        for m: Float in [1.02, 0.97, 1.06, 0.94, 1.0] {
            rig.handMagnification(m)
            XCTAssertEqual(rig.liveScale, 1, accuracy: 1e-6,
                           "a \(m)× wobble moved the view")
        }
        rig.endGesture()
        XCTAssertEqual(rig.scale, 1, accuracy: 1e-6)
    }

    func testPastTheBandTheViewGrowsFromWhereItStood() {
        let rig = rig()
        rig.handMagnification(1.05)
        rig.handMagnification(1.10)
        XCTAssertEqual(rig.liveScale, 1, accuracy: 1e-6,
                       "the view jumped by the band it waited out")
        rig.handMagnification(2.2)
        XCTAssertEqual(rig.liveScale, 2, accuracy: 1e-5,
                       "once engaged the view must follow the hands in proportion")
        rig.endGesture()
        XCTAssertEqual(rig.scale, 2, accuracy: 1e-5)
    }

    func testClosingTheHandsShrinksTheSameWay() {
        let rig = rig()
        rig.handMagnification(0.95)
        XCTAssertEqual(rig.liveScale, 1, accuracy: 1e-6)
        rig.handMagnification(0.9)
        rig.handMagnification(0.45)
        XCTAssertEqual(rig.liveScale, 0.5, accuracy: 1e-5)
    }

    func testEachGestureWaitsOutItsOwnBand() {
        let rig = rig()
        rig.handMagnification(1.2)
        rig.handMagnification(1.8)
        rig.endGesture()
        XCTAssertEqual(rig.scale, 1.5, accuracy: 1e-5)
        rig.handMagnification(1.05)
        XCTAssertEqual(rig.liveScale, 1.5, accuracy: 1e-5,
                       "the second gesture inherited the first one's engagement")
    }

    func testSpreadingTheHandsDoesNotTurnTheView() {
        let rig = rig()
        let wobble = degrees(6)
        rig.handMagnification(1.5)
        rig.handRotation(radians: wobble)
        XCTAssertEqual(rig.liveTurn, 0, accuracy: 1e-6,
                       "a resize brought a twist along with it")
        rig.handRotation(radians: degrees(12))
        XCTAssertEqual(rig.liveTurn, 0, accuracy: 1e-6,
                       "the turn jumped by the band it waited out")
        rig.handRotation(radians: degrees(42))
        XCTAssertEqual(rig.liveTurn, degrees(30), accuracy: 1e-5)
    }

    func testATurnOnlyRigIgnoresTheHandsTurn() {
        let rig = SpatialScaleRig(pivot: .zero, allowsTurn: false)
        rig.handRotation(radians: 1)
        XCTAssertEqual(rig.liveTurn, 0)
    }

    func testAnExactMagnificationSkipsTheBand() {
        // `-viewScale` sets a scale outright; the band is the hands' alone.
        let rig = rig()
        rig.updateMagnification(2.5)
        rig.endGesture()
        XCTAssertEqual(rig.scale, 2.5, accuracy: 1e-6)
    }

    func testCancellingAfterTheBandRestoresTheView() {
        let rig = rig()
        rig.handMagnification(1.2)
        rig.handMagnification(2.4)
        rig.cancelGesture()
        XCTAssertEqual(rig.liveScale, 1, accuracy: 1e-6)
        rig.handMagnification(1.05)
        XCTAssertEqual(rig.liveScale, 1, accuracy: 1e-6,
                       "a cancelled gesture left its engagement behind")
    }
}

private func degrees(_ value: Float) -> Float {
    value * .pi / 180
}
