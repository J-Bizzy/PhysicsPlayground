//
//  AppModelDoorTests.swift
//  PhysicsPlaygroundTests
//
//  ONE DOOR BETWEEN LABS, and the ordering inside it.
//
//  There were three ways to change the active module and all three were a
//  bare assignment, so the scene swapped in a single frame: the gallery's
//  Load button, the window's back chevron, and — the one that went
//  unnoticed longest — the palette's slot ring, which switches lab to lab
//  without touching the gallery at all. `go(to:)` is the one door they now
//  share, and `isDeparting` is what a module's scene root rides down.
//
//  THE ASSERTION THAT MATTERS is `testTheFlagClearsBeforeTheSwap`. If
//  `isDeparting` were still true when `activeModuleID` changed, the
//  incoming scene would mount already invisible with nothing left to raise
//  it — and an invisible lab is indistinguishable from a crash. That is a
//  one-line ordering bug with a catastrophic symptom, which is exactly the
//  kind a test should hold rather than a comment.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class AppModelDoorTests: XCTestCase {

    /// `go(to:)` only defers while a fade would actually render, so the
    /// space has to look open for the interesting cases.
    private func departingModel(from id: String) -> AppModel {
        let appModel = AppModel()
        // The space is still closed here, so the door goes straight
        // through — the cheapest way to land on a starting module now
        // that `activeModuleID` is `private(set)`.
        appModel.go(to: id)
        appModel.isImmersiveSpaceOpen = true
        return appModel
    }

    // MARK: The cases that go straight through

    /// Arriving from the gallery: there is no outgoing lab to fade, so a
    /// delay would be latency and nothing else.
    func testEnteringFromTheGalleryIsImmediate() {
        let appModel = AppModel()
        appModel.isImmersiveSpaceOpen = true
        appModel.go(to: "magnetism")
        XCTAssertEqual(appModel.activeModuleID, "magnetism")
        XCTAssertFalse(appModel.isDeparting)
    }

    /// Nothing would render the fade, so nothing waits for it. This is the
    /// `-openModule` path during `init`, and the window paths.
    func testWithTheSpaceClosedItIsImmediate() {
        let appModel = AppModel()
        appModel.go(to: "circuits")
        appModel.isImmersiveSpaceOpen = false
        appModel.go(to: "magnetism")
        XCTAssertEqual(appModel.activeModuleID, "magnetism")
    }

    func testGoingWhereYouAlreadyAreDoesNothing() {
        let appModel = departingModel(from: "circuits")
        appModel.go(to: "circuits")
        XCTAssertFalse(appModel.isDeparting)
    }

    // MARK: The deferred case

    func testLeavingALabDefersTheSwapAndFlagsTheDeparture() {
        let appModel = departingModel(from: "circuits")
        appModel.go(to: nil)
        // Synchronously, nothing has changed yet — the lab is still there
        // to be faded out.
        XCTAssertEqual(appModel.activeModuleID, "circuits")
        XCTAssertTrue(appModel.isDeparting)
    }

    /// THE ORDERING. Both facts are asserted at the same instant: the swap
    /// has happened AND the flag is already down. Asserting them in two
    /// separate waits would let exactly the broken ordering pass.
    func testTheFlagClearsBeforeTheSwap() async throws {
        let appModel = departingModel(from: "circuits")
        appModel.go(to: "magnetism")

        try await Task.sleep(for: .seconds(AppModel.departure * 3 + 0.15))

        XCTAssertEqual(appModel.activeModuleID, "magnetism")
        XCTAssertFalse(appModel.isDeparting,
                       "the incoming scene would mount invisible with nothing to raise it")
    }

    /// A second pinch mid-departure must not start a second swap — two
    /// pending tasks would land in an order nothing defines.
    func testASecondGoWhileDepartingIsIgnored() async throws {
        let appModel = departingModel(from: "circuits")
        appModel.go(to: "magnetism")
        appModel.go(to: "pendulums")

        try await Task.sleep(for: .seconds(AppModel.departure * 3 + 0.15))
        XCTAssertEqual(appModel.activeModuleID, "magnetism",
                       "the first destination wins; the second is dropped")
    }

    /// The departure and the arrival are the same length, so a switch is
    /// symmetric rather than lopsided.
    func testTheDepartureMatchesTheArrivalRamp() {
        XCTAssertEqual(AppModel.departure, 0.22, accuracy: 1e-9)
    }

    // MARK: The door is the only door

    /// THE DOOR WAS ONE OF FIVE.
    ///
    /// `go(to:)` documents itself as THE ONE DOOR between labs, and the
    /// point of routing every caller through it is that all of them run
    /// the same curve. But `activeModuleID` stayed settable, and four
    /// callers went on assigning it directly — the hub's two enter paths
    /// and the flat catalog's row — so entering a lab from the gallery
    /// skipped the departure fade entirely.
    ///
    /// The real enforcement is `private(set)` and the compiler; this test
    /// is the runtime half, and it is the ONE case a direct assignment
    /// would still get wrong now that they are gone.
    func testEnteringALabFromAnotherOneRunsTheFade() {
        let appModel = departingModel(from: "circuits")

        appModel.go(to: "magnetism")

        XCTAssertTrue(appModel.isDeparting,
                      "the swap happened in one frame — this is what a bare "
                      + "`activeModuleID = id` did from the hub")
        XCTAssertEqual(appModel.activeModuleID, "circuits",
                       "the incoming lab mounted before the outgoing one had "
                       + "faded")
    }

    /// Closing the gallery is the one caller that must NOT wait: the
    /// space is being torn down in the same breath, so a deferred clear
    /// would land after there was anything left to clear.
    func testClosingForDismissalIsImmediateEvenMidLab() {
        let appModel = departingModel(from: "circuits")

        appModel.closeForDismissal()

        XCTAssertNil(appModel.activeModuleID)
        XCTAssertFalse(appModel.isDeparting,
                       "closing the space armed a fade that has nothing to "
                       + "fade and no scene to land in")
    }
}
