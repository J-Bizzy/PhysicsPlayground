//
//  SurroundingsTests.swift
//  PhysicsPlaygroundTests
//
//  The room or deep space (2026-10-20): the room is the default; the
//  wearer's choice is remembered; a lab with a preference of its own
//  (Orbital Mechanics) opens in it whatever was chosen, until the wearer
//  chooses again there; deep space is full immersion and the room keeps
//  each lab's own style; and a launch straight into a lab resolves all of
//  it in `init`, where no observer fires.
//

import XCTest
import SwiftUI
@testable import PhysicsPlayground

@MainActor
final class SurroundingsTests: XCTestCase {

    private static let keys = ["settings.surroundings", "openModule"]

    override func setUp() {
        super.setUp()
        Self.keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        Self.keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    /// `ImmersionStyle` is a protocol with no equality: its name, then.
    private func style(_ app: AppModel) -> String {
        switch app.immersionStyle {
        case is FullImmersionStyle: "full"
        case is ProgressiveImmersionStyle: "progressive"
        case is MixedImmersionStyle: "mixed"
        default: "other"
        }
    }

    func testALabsOwnPreferenceWinsForItsVisit() {
        XCTAssertEqual(Surroundings.resolve(choice: .room, labPrefers: nil), .room)
        XCTAssertEqual(Surroundings.resolve(choice: .deepSpace, labPrefers: nil), .deepSpace)
        XCTAssertEqual(Surroundings.resolve(choice: .room, labPrefers: .deepSpace), .deepSpace)
        XCTAssertEqual(Surroundings.resolve(choice: .deepSpace, labPrefers: .room), .room)
    }

    func testTheLaunchArgumentsSpelling() {
        XCTAssertEqual(Surroundings(argument: "space"), .deepSpace)
        XCTAssertEqual(Surroundings(argument: "room"), .room)
        XCTAssertNil(Surroundings(argument: "studio"))
    }

    /// The room is where the app opens, in the room's own style.
    func testTheRoomIsTheDefault() {
        let app = AppModel()
        XCTAssertEqual(app.surroundings, .room)
        XCTAssertEqual(style(app), "mixed")
    }

    /// Choosing deep space is full immersion at once, and survives a relaunch.
    func testTheChoiceIsFullImmersionAndRemembered() {
        let app = AppModel()
        app.choose(.deepSpace)
        XCTAssertEqual(app.surroundings, .deepSpace)
        XCTAssertEqual(style(app), "full")
        app.go(to: "pendulums")
        XCTAssertEqual(app.surroundings, .deepSpace, "a lab with no preference follows the choice")
        XCTAssertEqual(style(app), "full")

        let relaunched = AppModel()
        XCTAssertEqual(relaunched.surroundings, .deepSpace)
        XCTAssertEqual(style(relaunched), "full")
        relaunched.choose(.room)
        XCTAssertEqual(style(relaunched), "mixed")
        XCTAssertEqual(AppModel().surroundings, .room)
    }

    /// Orbital Mechanics opens in space from the room; choosing the room
    /// there brings it back now, in the lab's own room style; the next
    /// visit is in space again.
    func testOrbitalMechanicsOpensInSpaceUntilTheWearerChoosesTheRoom() {
        let app = AppModel()
        app.go(to: OrbitalMechanicsModule.id)
        XCTAssertEqual(app.surroundings, .deepSpace)
        XCTAssertEqual(style(app), "full")

        app.choose(.room)
        XCTAssertEqual(app.surroundings, .room)
        XCTAssertEqual(style(app), "progressive", "the lab's own style in the room")
        XCTAssertEqual(app.roomDimming, 0.85, "and its own atmosphere")

        app.go(to: nil)
        XCTAssertEqual(app.surroundings, .room)
        XCTAssertEqual(style(app), "mixed")
        app.go(to: OrbitalMechanicsModule.id)
        XCTAssertEqual(app.surroundings, .deepSpace, "its preference holds for each visit")
    }

    /// A launch straight into Orbital Mechanics (`-openModule`) sets the
    /// lab in `init`, where `didSet` never runs: it must still open in
    /// space, with the lab's atmosphere, not on .mixed at the home's.
    func testALaunchStraightIntoALabResolvesItInInit() {
        UserDefaults.standard.set(OrbitalMechanicsModule.id, forKey: "openModule")
        let app = AppModel()
        XCTAssertEqual(app.activeModuleID, OrbitalMechanicsModule.id)
        XCTAssertEqual(app.surroundings, .deepSpace)
        XCTAssertEqual(style(app), "full")
        XCTAssertEqual(app.roomDimming, 0.85)
        XCTAssertEqual(app.dimmingRadius, 16)
    }
}
