//
//  SettleTests.swift
//  PhysicsPlaygroundTests
//
//  A freshly mounted scene shows itself only once it has run clean
//  frames in a row (2026-10-20): every lab and the home dropped frames of
//  30–250 ms just after mounting, and their arrivals stuttered through
//  them. These hold the rule — clean frames settle it, a long one starts
//  the count again, a scene that never makes the budget still shows, and
//  the home's opening waits with its clock at zero.
//

import XCTest
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class SettleTests: XCTestCase {

    private let frame = 1.0 / 90.0

    func testCleanFramesInARowSettleAScene() {
        var settle = Settle()
        for _ in 0..<(Settle.cleanFrames - 1) {
            XCTAssertFalse(settle.tick(dt: frame))
        }
        XCTAssertTrue(settle.tick(dt: frame))
        XCTAssertTrue(settle.tick(dt: 0.5), "settled stays settled, whatever comes after")
    }

    func testALongFrameStartsTheCountAgain() {
        var settle = Settle()
        for _ in 0..<(Settle.cleanFrames - 1) { settle.tick(dt: frame) }
        XCTAssertFalse(settle.tick(dt: 0.12), "a 120 ms frame is not clean")
        for _ in 0..<(Settle.cleanFrames - 1) {
            XCTAssertFalse(settle.tick(dt: frame))
        }
        XCTAssertTrue(settle.tick(dt: frame))
    }

    /// A device that never makes the budget still shows the scene, after a
    /// count of frames — not a time, which one multi-second first delta
    /// would spend at once.
    func testAStragglingSceneStillShows() {
        var settle = Settle()
        XCTAssertFalse(settle.tick(dt: 4.0), "one huge first delta must not settle it")
        for _ in 1..<(Settle.frameCap - 1) {
            XCTAssertFalse(settle.tick(dt: 0.02))
        }
        XCTAssertTrue(settle.tick(dt: 0.02))
    }

    /// The home's arrival holds its clock at zero until the scene settles:
    /// the labs wait drawn but unseen, at the start of their rise.
    func testTheArrivalWaitsForTheSceneToSettle() {
        let scene = HubScene()
        scene.build(modules: ModuleCatalog.all(appModel: AppModel()))
        XCTAssertTrue(scene.isOpening)
        // Long frames, as a mount brings: the arrival does not move.
        for _ in 0..<5 { scene.animate(dt: 0.1) }
        XCTAssertEqual(scene.openingClock, 0, accuracy: 1e-9)
        // Clean frames settle it, and the clock runs from then.
        for _ in 0..<(Settle.cleanFrames + 9) { scene.animate(dt: frame) }
        XCTAssertGreaterThan(scene.openingClock, 0)
        XCTAssertLessThan(scene.openingClock, 0.2, "the clock ran during the hold")
    }
}
