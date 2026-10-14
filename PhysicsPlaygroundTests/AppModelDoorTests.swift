//
//  AppModelDoorTests.swift
//  PhysicsPlaygroundTests
//
//  One door between labs (`go(to:)`), and the ordering inside it:
//  `isDeparting` must clear before `activeModuleID` changes, or the
//  incoming scene mounts invisible.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class AppModelDoorTests: XCTestCase {

    /// `go(to:)` only defers while a fade would actually render, so the
    /// space has to look open for the interesting cases.
    private func departingModel(from id: String) -> AppModel {
        let appModel = AppModel()
        // The space is still closed here, so the door goes straight through.
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

    /// Both facts asserted at the same instant: the swap has happened and
    /// the flag is already down.
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

    /// Entering a lab from another one runs the fade — the one case a
    /// direct assignment to `activeModuleID` would get wrong.
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

    /// Closing the gallery is the one caller that must not wait: the
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
