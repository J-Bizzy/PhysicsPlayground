//
//  RoomSessionTests.swift
//  PhysicsPlaygroundTests
//
//  Opening a second module once killed the process: a stopped ARKit
//  provider cannot be run again, and the NSException it raises unwinds
//  past `catch`. The session must be rebuilt per start, and overlapping
//  retains must not both reach `run`.
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

    // MARK: The room says when it cannot see the room

    /// `sensing` may only say `.fine` when sensing is actually running —
    /// asserted as an iff, because which branch the simulator takes depends
    /// on which providers it supports.
    @MainActor
    func testTheRoomNeverClaimsToBeSensingWhenItIsNot() async {
        let room = RoomModel()
        XCTAssertEqual(room.sensing, .fine,
                       "a room nobody has asked for anything has nothing to report")

        await room.retain()

        XCTAssertEqual(
            room.sensing == .fine, room.isRunning,
            """
            After retain() the room is running=\(room.isRunning) but reports \
            \(room.sensing). `.fine` means "nothing to say"; anything else \
            means the shell puts a warning in the title bar. Those two have \
            to agree, or the app is either crying wolf or — the case this \
            exists for — silently doing less than the user thinks.
            """)
        room.release()
    }

    /// Leaving during a start must still take the session down: `release()`
    /// was guarded on `isRunning`, which stays false for the whole of
    /// `retain()`, so a release during the permission sheet no-oped and the
    /// providers ran for the life of the process with no clients.
    @MainActor
    func testReleasingDuringAStartLeavesNothingPinnedOpen() async {
        let room = RoomModel()

        let starting = Task { await room.retain() }
        // Interleave: the release lands while the retain is in flight.
        await Task.yield()
        room.release()
        await starting.value

        XCTAssertEqual(room.clientCount, 0,
                       "the release did not balance its retain")
        XCTAssertFalse(room.hasClients)

        try? await Task.sleep(for: .seconds(RoomModel.testLingerSeconds + 0.6))
        XCTAssertFalse(room.isRunning,
                       "the session outlived its last client — this is the leak: "
                       + "sensors running for the process lifetime with nobody "
                       + "reading them")
    }

    /// The cases are distinct on purpose: the worst version is one message
    /// with a variable in it, telling a simulator user to grant a permission
    /// they were never asked for.
    func testEachSensingCaseIsDistinct() {
        let all: [RoomModel.Sensing] = [.fine, .unsupported, .denied, .failed]
        for (index, one) in all.enumerated() {
            for other in all[(index + 1)...] {
                XCTAssertNotEqual(one, other)
            }
        }
    }
}
