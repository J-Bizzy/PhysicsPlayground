//
//  AppModelDoorTests.swift
//  PhysicsPlaygroundTests
//
//  One door between scenes (`go(to:)`). Since 2026-11-02 it holds: the
//  scene being left stays mounted and drawn while the next one builds and
//  settles behind it, then the two cross-fade — the room never stands
//  empty between them. Until then the old scene faded out first and the
//  new one mounted after, with nothing on screen while it settled.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class AppModelDoorTests: XCTestCase {

    /// The door only holds while the space is open to draw it.
    private func openModel(at id: String? = nil) -> AppModel {
        let appModel = AppModel()
        // The space is still closed here, so the door goes straight through.
        appModel.go(to: id)
        appModel.isImmersiveSpaceOpen = true
        return appModel
    }

    // MARK: Straight through

    /// Nothing would render the hold, so nothing waits for it. This is the
    /// `-openModule` path during `init`, and the window paths.
    func testWithTheSpaceClosedItIsImmediate() {
        let appModel = AppModel()
        appModel.go(to: "circuits")
        appModel.go(to: "magnetism")
        XCTAssertEqual(appModel.activeModuleID, "magnetism")
        XCTAssertEqual(appModel.mountedScenes, [.lab("magnetism")])
    }

    func testGoingWhereYouAlreadyAreDoesNothing() {
        let appModel = openModel(at: "circuits")
        appModel.go(to: "circuits")
        XCTAssertNil(appModel.leavingScene)
        XCTAssertEqual(appModel.mountedScenes, [.lab("circuits")])
    }

    // MARK: The hold

    /// Entering a lab: the lab is current at once (its window, its
    /// surroundings), and the home stays on screen beside it until the
    /// lab has settled; then the home fades and leaves.
    func testEnteringHoldsTheHomeUntilTheLabHasSettled() async throws {
        let appModel = openModel()
        appModel.go(to: "magnetism")
        XCTAssertEqual(appModel.activeModuleID, "magnetism")
        XCTAssertEqual(appModel.mountedScenes, [.home, .lab("magnetism")])
        XCTAssertTrue(appModel.isShown(.home), "the home holds while the lab builds")

        appModel.sceneSettled(.lab("magnetism"))
        XCTAssertFalse(appModel.isShown(.home), "the lab is up: the home fades")
        XCTAssertTrue(appModel.isShown(.lab("magnetism")))

        try await Task.sleep(for: .seconds(AppModel.departure + 0.2))
        XCTAssertEqual(appModel.mountedScenes, [.lab("magnetism")])
    }

    /// Only the scene the door is waiting on releases it: the leaving
    /// scene settling (it was already up) changes nothing.
    func testOnlyTheIncomingSceneReleasesTheHold() {
        let appModel = openModel(at: "circuits")
        appModel.go(to: nil)
        appModel.sceneSettled(.lab("circuits"))
        XCTAssertTrue(appModel.isShown(.lab("circuits")))
        XCTAssertEqual(appModel.mountedScenes, [.lab("circuits"), .home])
    }

    /// A scene that never says it has settled cannot hold the door shut.
    func testAHoldNeverOutlastsItsLimit() async throws {
        let appModel = openModel(at: "circuits")
        appModel.go(to: "magnetism")
        try await Task.sleep(for: .seconds(AppModel.holdLimit + AppModel.departure + 0.3))
        XCTAssertEqual(appModel.mountedScenes, [.lab("magnetism")])
    }

    /// A second pinch mid-hold starts no second door: two holds would land
    /// in an order nothing defines.
    func testASecondGoWhileHoldingIsIgnored() {
        let appModel = openModel(at: "circuits")
        appModel.go(to: "magnetism")
        appModel.go(to: "pendulums")
        XCTAssertEqual(appModel.activeModuleID, "magnetism",
                       "the first destination wins; the second is dropped")
    }

    /// A lab on its way out holds where it stood: the placement is the
    /// next lab's from the moment the door opens.
    func testALeavingLabHoldsItsPlacement() {
        let appModel = openModel(at: "circuits")
        appModel.go(to: "magnetism")
        XCTAssertNil(appModel.placement(forLab: "circuits"))
        XCTAssertEqual(appModel.placement(forLab: "magnetism"), appModel.labPlacement.offset)
    }

    /// The cross-fade and a scene's own arrival are one length.
    func testTheCrossFadeMatchesTheArrivalRamp() {
        XCTAssertEqual(AppModel.departure, 0.22, accuracy: 1e-9)
    }

    /// Closing the space is the one caller that must not wait: it is being
    /// torn down in the same breath, so a hold would outlive its scenes.
    func testClosingForDismissalIsImmediateEvenMidHold() {
        let appModel = openModel(at: "circuits")
        appModel.go(to: "magnetism")
        appModel.closeForDismissal()
        XCTAssertNil(appModel.activeModuleID)
        XCTAssertNil(appModel.leavingScene)
        XCTAssertEqual(appModel.mountedScenes, [.home])
    }
}
