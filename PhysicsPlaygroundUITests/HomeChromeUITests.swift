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
//  is addressable: not the exhibits, not the podium, not a magnet, not
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

        // The catalog is REPLACED by the module. Asserting on what
        // disappears rather than what appears is the robust shape here:
        // a lab's own window chrome varies per module, but the home's
        // catalog is gone in every case, and a row that is still there
        // means the tap did nothing.
        let entered = app.buttons["Add part"].waitForExistence(timeout: 20)
            || app.staticTexts["Bench"].waitForExistence(timeout: 2)
        let catalogGone = !app.buttons["Gravity Lab"].exists
        XCTAssertTrue(entered || catalogGone,
                      "tapping Circuit Workshop left the home exactly as it "
                      + "was: catalog still up, no lab controls. Either the "
                      + "row is not receiving the tap or its action is not "
                      + "wired.")
    }
}
