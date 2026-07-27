//
//  RoomSessionTests.swift
//  PhysicsPlaygroundTests
//
//  The crash this file exists to prevent:
//
//      RoomModel.retain()
//      ARKitSession.run(_:)
//      objc_exception_throw
//      abort()
//
//  Opening one module worked. Opening a SECOND one killed the process,
//  which is exactly what "a lot of the modules glitch the program out"
//  looks like from the outside. The cause was that RoomModel held its
//  ARKitSession and its four data providers as constants built once at
//  init: `session.stop()` retires a provider permanently, so the second
//  `run` handed ARKit objects it had already finished with, and ARKit
//  answered with an Objective-C exception — which is not a Swift error,
//  so the `do/catch` around `run` never saw it and the process aborted.
//
//  Both invariants below are about that. The session must be rebuilt
//  per start, and overlapping retains must not both reach `run`.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class RoomSessionTests: XCTestCase {

    /// Enter a module, leave, enter another. This is the sequence that
    /// aborted; reaching the end of it at all is the assertion.
    func testRestartAfterFullReleaseDoesNotAbort() async {
        let room = RoomModel()

        await room.retain()
        room.release()
        // Past the linger window, so the session genuinely stops rather
        // than being handed back to the next module still running.
        try? await Task.sleep(for: .seconds(RoomModel.testLingerSeconds + 0.6))

        await room.retain()
        room.release()

        XCTAssertFalse(room.hasClients,
                       "Every retain was released; the session must not be pinned open.")
    }

    /// Several views retain the room at once — the module scene, the
    /// occlusion view, the lab anchor. Overlapping is the normal case,
    /// and two concurrent `run` calls is one of the ways ARKit aborts.
    func testConcurrentRetainsStartTheSessionOnce() async {
        let room = RoomModel()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { @MainActor in await room.retain() }
            }
        }
        XCTAssertEqual(room.clientCount, 6)

        for _ in 0..<6 { room.release() }
        XCTAssertFalse(room.hasClients)
    }

    /// A module switch tears the old scene down and builds the new one,
    /// and SwiftUI does not promise the order. Whichever way round it
    /// happens, the sensors must not be stopped and restarted for it.
    func testSwitchingModulesKeepsTheSessionUp() async {
        let room = RoomModel()

        await room.retain()          // module A on screen
        room.release()               // A disappears...
        await room.retain()          // ...and B appears within the linger
        try? await Task.sleep(for: .seconds(RoomModel.testLingerSeconds + 0.6))

        XCTAssertTrue(room.hasClients,
                      "B still holds the room; the linger must not have torn it down.")
        room.release()
    }
}
