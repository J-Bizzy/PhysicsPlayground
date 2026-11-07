//
//  WindowLifecycleTests.swift
//  PhysicsPlaygroundTests
//
//  A lab's window is its title bar, and the bar is the only way to Home,
//  More and Pause. Closed by hand, nothing brought it back (2026-11-07):
//  the lab ran on with no way out but the Digital Crown. Now the lab goes
//  home, the one scene built to stand without a window.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class WindowLifecycleTests: XCTestCase {

    /// A lab active with the space open and the window going: a hand closed it.
    func testClosingALabsBarGoesHome() {
        XCTAssertTrue(MainWindowView.closingGoesHome(activeModuleID: "pendulums", spaceOpen: true))
    }

    /// The app's own dismissal on the way home clears the module first.
    func testTheAppsOwnDismissalDoesNothingMore() {
        XCTAssertFalse(MainWindowView.closingGoesHome(activeModuleID: nil, spaceOpen: true))
    }

    /// With the space closed the window is the whole app: closing it is
    /// leaving, not a stranding, and the space's own leaf reopens a window
    /// when the space goes.
    func testClosingTheWindowWithNoSpaceIsLeaving() {
        XCTAssertFalse(MainWindowView.closingGoesHome(activeModuleID: "pendulums", spaceOpen: false))
        XCTAssertFalse(MainWindowView.closingGoesHome(activeModuleID: nil, spaceOpen: false))
    }
}
