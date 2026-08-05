//
//  HomeChromeUITests.swift
//  Physics Playground — UI tests
//
//  The only tests in this project that actually PRESS things.
//
//  Everything else here verifies by calling code or by looking at a
//  screenshot. Neither catches a button wired to nothing: a screenshot
//  proves the button was drawn, and a unit test proves the action would
//  work IF something called it. The gap between those two is exactly
//  where "I tapped it and nothing happened" lives.
//
//  SCOPE, stated honestly, because the boundary is not obvious:
//  XCUITest can drive SwiftUI — windows, buttons, pickers, lists. It
//  has NO API for RealityKit entities. Nothing in the immersive space
//  is addressable: not the exhibits, not the pad, not a magnet, not
//  a two-handed pinch. Those are covered by `StationTapTests` at the
//  handler level and by `docs/ON_DEVICE_TESTS.md` in a headset, and
//  they cannot be covered here. A test file that pretended otherwise
//  would be worse than this comment.
//

import XCTest

final class HomeChromeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // The window catalog is the reliable surface in the simulator:
        // it is what the home shows before (or instead of) the immersive
        // gallery, and it is the accessibility path the standing rule
        // requires anyway — nothing may be reachable only in space.
        app.launchArguments += ["-uiTesting", "1"]
        app.launch()
    }

    override func tearDown() {
        app = nil
    }

    /// The app comes up and names itself. If this fails, every other
    /// test in the file is failing for the same uninteresting reason.
    func testTheAppLaunchesAndShowsItsName() {
        XCTAssertTrue(app.staticTexts["Physics Playground"].waitForExistence(timeout: 20),
                      "the home window never appeared")
    }

    /// Every experience is reachable from the flat catalog, by name.
    /// This is the accessibility path: if a lab can only be entered by
    /// dragging an exhibit in space, it is unreachable for anyone not
    /// using their hands, and unreachable in the simulator entirely.
    func testEveryExperienceIsListedByName() {
        XCTAssertTrue(app.staticTexts["Physics Playground"].waitForExistence(timeout: 20))
        for id in ["electrostatics", "circuits", "magnetism",
                   "kinematics", "pendulums", "gravitylab"] {
            XCTAssertTrue(
                app.buttons["lab.\(id)"].waitForExistence(timeout: 5),
                "\(id) is not reachable as a named control in the window "
                + "catalog — VoiceOver cannot announce it either")
        }
    }

    /// Both domain groups are named in the catalog, so the two doors
    /// read the same flat as they do in space.
    func testBothDomainsAreNamedInTheCatalog() {
        XCTAssertTrue(app.staticTexts["Physics Playground"].waitForExistence(timeout: 20))
        for domain in ["Electricity & Magnetism", "Mechanics & Energy"] {
            XCTAssertTrue(app.staticTexts[domain].waitForExistence(timeout: 5),
                          "\(domain) is missing from the catalog")
        }
    }

    /// Entering a lab from the catalog actually changes what is on
    /// screen. This is the "the button does nothing" test: the row is
    /// drawn either way, and only pressing it proves it is wired.
    func testTappingALabEntersIt() {
        XCTAssertTrue(app.staticTexts["Physics Playground"].waitForExistence(timeout: 20))
        let row = app.buttons["lab.circuits"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // The catalog is REPLACED by the module's window.
        //
        // This used to wait for `Add part`, a button on Circuit
        // Workshop's control panel. There are no control panels
        // (DECISIONS.md, 2026-08-01) and there is no `Add part` — parts
        // come off a tray in the room, which XCUITest cannot see at all.
        //
        // "Show in room" is the right replacement, and not merely
        // because it survived. Under `-uiTesting 1` the immersive space
        // is deliberately held back (`HubView.isUITesting`), so this
        // button is on screen for exactly this run; it is a real
        // capability rather than a decorative label; and it is one of
        // the three things the module window is now allowed to contain.
        //
        // It is deliberately NOT `app.staticTexts["Circuit Workshop"]`:
        // the catalog row carries that same string as its accessibility
        // label, so that assertion would have passed before the tap.
        let entered = app.buttons["Show in room"].waitForExistence(timeout: 20)
        XCTAssertTrue(entered,
                      "tapping Circuit Workshop did not open its window: no "
                      + "\"Show in room\" appeared. Either the row is not "
                      + "receiving the tap or its action is not wired.")
        XCTAssertFalse(app.buttons["lab.gravitylab"].exists,
                       "the module opened but the catalog is still up behind it")
    }

    /// The settings window's two actions exist as named, pressable
    /// buttons. The window restyled onto the house button styles on
    /// 2026-08-05; a style is applied to a `Button`, so if either row
    /// ever degrades into styled text this stops finding it — the same
    /// "drawn is not wired" gap the tap test above exists for.
    func testTheSettingsWindowShowsItsActions() {
        app.terminate()
        app.launchArguments += ["-settingsOpen", "1"]
        app.launch()

        XCTAssertTrue(app.buttons["Show hints again"].waitForExistence(timeout: 20),
                      "the settings window never showed its onboarding action")
        XCTAssertTrue(app.buttons["Reset experiment progress…"].exists,
                      "the destructive progress reset is missing from settings")
    }
}
