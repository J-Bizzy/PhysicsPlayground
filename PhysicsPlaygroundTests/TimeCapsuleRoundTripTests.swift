//
//  TimeCapsuleRoundTripTests.swift
//  PhysicsPlaygroundTests
//
//  The Time Capsule's adoption contract, proved per module.
//
//  THE REPLAY-DETERMINISM TEST IS THE ENUMERATING GUARD. A snapshot
//  field somebody forgets is invisible until a scrub lies — the exact
//  shape of the reset()-coverage defect this project has now shipped six
//  times, transposed to a new surface. A test that LISTS the fields it
//  knows about is the same act of attention that would miss one. So do
//  not weaken these to listing tests: restore-to-mid-window and re-step
//  with the identical dt sequence, and any dynamical field missing from
//  the snapshot (a substep accumulator, a velocity map) makes the replay
//  diverge measurably from the recording.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class TimeCapsuleRoundTripTests: XCTestCase {

    /// A bare, deterministic bench: no welcome scene, no real room, no
    /// walls — pure floor physics under a fixed clock.
    private func bareModel() -> KinematicsModel {
        let model = KinematicsModel()
        model.clearFlights()
        while !model.rings.isEmpty { model.removeLastRing() }
        model.roomWalls = []
        model.roomBounds = RoomBox(center: SIMD3(0, 50, 0),
                                   halfExtents: SIMD3(100, 50, 100))
        model.clearCapsule()
        return model
    }

    private let dt = 1.0 / 90.0

    // MARK: Kinematics

    /// Capture → mutate → restore → re-capture equals the original.
    func testKinematicsSnapshotRoundTrip() {
        let model = bareModel()
        model.fire()
        for _ in 0..<30 { model.step(dt: dt) }

        let snapshot = model.captureCapsuleSnapshot()
        // Mutate well past the captured instant.
        model.fire()
        model.gravity = 3.7
        model.windSpeed = 5
        for _ in 0..<60 { model.step(dt: dt) }

        model.restoreCapsuleSnapshot(snapshot)
        XCTAssertEqual(model.captureCapsuleSnapshot(), snapshot)
    }

    /// Restore to mid-window and re-step with the identical dt sequence:
    /// the replay must retrace the recording. This is the test that
    /// catches a forgotten snapshot field — see the header.
    func testKinematicsReplayRetracesTheRecording() {
        let model = bareModel()
        model.fire()
        for _ in 0..<120 { model.step(dt: dt) }

        // The capsule recorded a frame per step. Scrub back one second…
        model.isPaused = true
        model.scrub(toOffset: 1.0)
        let scrubbed = try! XCTUnwrap(model.scrubTime)

        // …collect what the recording says the next 60 frames were…
        let recorded = model.capsule.frames(
            in: scrubbed...(scrubbed + 61 * dt))

        // …resume and re-step through them with the same dt.
        model.commitScrubAndResume()
        for frame in recorded.dropFirst() {
            model.step(dt: dt)
            let replayed = model.flights
            let original = frame.snapshot.flights
            XCTAssertEqual(replayed.count, original.count)
            for (a, b) in zip(replayed, original) {
                XCTAssertEqual(a.id, b.id)
                XCTAssertLessThan(
                    simd_distance(a.state.position, b.state.position), 1e-12,
                    "Replay diverged from the recording — a dynamical field is missing from CapsuleSnapshot"
                )
                XCTAssertLessThan(
                    simd_distance(a.state.velocity, b.state.velocity), 1e-12)
            }
        }
    }

    /// Scrubbing lands on recorded frames, pauses the model, and the
    /// restored state is what the recording says stood at that instant.
    func testKinematicsScrubRestoresRecordedInstant() {
        let model = bareModel()
        model.fire()
        for _ in 0..<90 { model.step(dt: dt) }
        let positionBefore = model.flights[0].state.position

        model.isPaused = true
        model.scrub(toOffset: 0.5)
        XCTAssertTrue(model.isPaused)
        let scrubbedTime = try! XCTUnwrap(model.scrubTime)
        let frame = try! XCTUnwrap(model.capsule.frame(at: scrubbedTime))
        XCTAssertEqual(model.flights[0].state.position,
                       frame.snapshot.flights[0].state.position)
        XCTAssertNotEqual(model.flights[0].state.position, positionBefore)
    }

    /// Un-pausing from a scrubbed instant truncates the rejected future
    /// and recording continues from there — the rewind-and-rerun path.
    func testKinematicsResumeTruncatesTheFuture() {
        let model = bareModel()
        model.fire()
        for _ in 0..<90 { model.step(dt: dt) }
        let fullSpan = try! XCTUnwrap(model.capsuleSpan)

        model.isPaused = true
        model.scrub(toOffset: 0.6)
        let scrubbed = try! XCTUnwrap(model.scrubTime)
        model.togglePauseRespectingScrub()

        XCTAssertFalse(model.isPaused)
        XCTAssertNil(model.scrubTime)
        let truncated = try! XCTUnwrap(model.capsuleSpan)
        XCTAssertEqual(truncated.upperBound, scrubbed, accuracy: 1e-12)
        XCTAssertLessThan(truncated.upperBound, fullSpan.upperBound)

        model.step(dt: dt)
        let resumed = try! XCTUnwrap(model.capsuleSpan)
        XCTAssertGreaterThan(resumed.upperBound, scrubbed)
    }

    /// The pause petal's contract: toggling from live pauses without
    /// touching the recording; toggling from paused resumes.
    func testTogglePauseRespectingScrub() {
        let model = bareModel()
        model.fire()
        for _ in 0..<30 { model.step(dt: dt) }
        let span = try! XCTUnwrap(model.capsuleSpan)

        model.togglePauseRespectingScrub()
        XCTAssertTrue(model.isPaused)
        XCTAssertEqual(model.capsuleSpan, span)

        model.togglePauseRespectingScrub()
        XCTAssertFalse(model.isPaused)
    }

    /// reset() leaves no recorded past to scrub into.
    func testKinematicsResetClearsCapsule() {
        let model = bareModel()
        model.fire()
        for _ in 0..<30 { model.step(dt: dt) }
        model.isPaused = true
        model.scrub(toOffset: 0.1)

        model.reset()
        XCTAssertNil(model.scrubTime)
        // reset() fires the welcome shot but does not step — nothing has
        // been recorded since the clear.
        XCTAssertNil(model.capsuleSpan)
    }

    /// The present hand wins: a ball held right now is never moved by a
    /// restore, and a ball that was held in the snapshot comes back
    /// staged (the past hand is gone).
    func testKinematicsRestoreLeavesHeldBallAlone() {
        let model = bareModel()
        let heldID = model.spawnBall(at: SIMD3(0, 1.2, -1))
        model.grabBall(id: heldID)
        for _ in 0..<30 { model.step(dt: dt) }
        let snapshot = model.captureCapsuleSnapshot()

        // The hand carries the ball somewhere new after the capture.
        let handPosition = SIMD3(0.5, 1.5, -0.8)
        model.holdBall(id: heldID, at: handPosition, timestamp: 1.0)

        model.restoreCapsuleSnapshot(snapshot)
        let held = try! XCTUnwrap(model.flights.first { $0.id == heldID })
        XCTAssertEqual(held.state.position, handPosition)
        XCTAssertEqual(held.status, .held)

        // Release, then restore the same snapshot: the past hand is
        // gone, so the snapshot's held ball comes back staged.
        model.releaseBall(id: heldID, timestamp: 1.1)
        model.restoreCapsuleSnapshot(snapshot)
        let staged = try! XCTUnwrap(model.flights.first { $0.id == heldID })
        XCTAssertEqual(staged.status, .staged)
    }

    /// Frame-stepping moves exactly one recorded physics tick, pausing
    /// first if the model was live.
    func testKinematicsFrameStep() {
        let model = bareModel()
        model.fire()
        for _ in 0..<60 { model.step(dt: dt) }

        model.stepScrub(frames: -1)
        XCTAssertTrue(model.isPaused)
        let firstStep = try! XCTUnwrap(model.scrubTime)
        model.stepScrub(frames: -1)
        let secondStep = try! XCTUnwrap(model.scrubTime)
        XCTAssertEqual(firstStep - secondStep, dt, accuracy: 1e-9)

        model.stepScrub(frames: 1)
        XCTAssertEqual(try! XCTUnwrap(model.scrubTime), firstStep,
                       accuracy: 1e-12)
    }

    /// Every restore bumps the scrub nonce — the signal renderers use to
    /// reseed presentation caches after a discontinuous state jump.
    func testScrubBumpsNonce() {
        let model = bareModel()
        model.fire()
        for _ in 0..<30 { model.step(dt: dt) }
        let before = model.scrubNonce
        model.isPaused = true
        model.scrub(toOffset: 0.2)
        XCTAssertEqual(model.scrubNonce, before + 1)
        model.stepScrub(frames: -1)
        XCTAssertEqual(model.scrubNonce, before + 2)
    }
}
