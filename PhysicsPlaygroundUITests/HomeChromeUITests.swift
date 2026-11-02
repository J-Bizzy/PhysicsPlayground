//
//  HomeChromeUITests.swift
//  Physics Playground — UI tests
//
//  The only tests in this project that actually press things. XCUITest
//  can drive SwiftUI windows, buttons and lists; it has no API for
//  RealityKit entities, so nothing in the immersive space is addressable
//  here — that is `handleTap` at the handler level and the device script.
//

import XCTest

final class HomeChromeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // The window catalog is the reliable surface in the simulator, and the
        // accessibility path the standing rule requires anyway.
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

        // The catalog is replaced by the module's window. "Show in Room" is on
        // screen for exactly this run (the space is held back under
        // `-uiTesting`) and is a real capability. Not the module's title: the
        // catalog row carries that string as its accessibility label, so that
        // assertion would pass before the tap.
        let entered = app.buttons["Show in Room"].waitForExistence(timeout: 20)
        XCTAssertTrue(entered,
                      "tapping Circuit Workshop did not open its window: no "
                      + "\"Show in Room\" appeared. Either the row is not "
                      + "receiving the tap or its action is not wired.")
        XCTAssertFalse(app.buttons["lab.gravitylab"].exists,
                       "the module opened but the catalog is still up behind it")
    }

    /// The settings window opens from its launch argument and shows a named,
    /// operable control; a `Toggle` that degraded into styled text would
    /// stop being found here.
    func testTheSettingsWindowShowsItsControls() {
        app.terminate()
        app.launchArguments += ["-settingsOpen", "1"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 20),
                      "the settings window never appeared")
        let music = app.switches["Music"]
        XCTAssertTrue(music.waitForExistence(timeout: 5),
                      "the settings window has no operable music switch")
    }
}
