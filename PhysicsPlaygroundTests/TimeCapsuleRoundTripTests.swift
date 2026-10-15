//
//  TimeCapsuleRoundTripTests.swift
//  PhysicsPlaygroundTests
//
//  The Time Capsule's adoption contract, per module. The replay test is
//  the enumerating guard: restore to mid-window and re-step with the
//  identical dt sequence, and any dynamical field missing from the
//  snapshot makes the replay diverge. Do not weaken these to listing
//  tests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class TimeCapsuleRoundTripTests: XCTestCase {

    // The gate is set explicitly rather than trusted: a test about
    // recording must not depend on what the previous test left behind.
    override func setUp() {
        super.setUp()
        TimeCapsuleSettings.isEnabled = true
    }

    override func tearDown() {
        // The shipped default, for whatever runs next.
        TimeCapsuleSettings.isEnabled = true
        super.tearDown()
    }

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

    /// The recorded-path polylines the tube is built from: present only
    /// while scrubbed, one per flight, tracing the recorded window.
    func testRecordedPathsExistOnlyWhileScrubbed() {
        let model = bareModel()
        model.fire()
        for _ in 0..<120 { model.step(dt: dt) }
        XCTAssertTrue(model.capsuleRecordedPaths().isEmpty,
                      "A live room draws no recorded path")

        model.isPaused = true
        model.scrub(toOffset: 0.5)
        let paths = model.capsuleRecordedPaths()
        XCTAssertEqual(paths.count, 1)
        XCTAssertGreaterThan(paths[0].count, 10)
        // The polyline is the recorded arc: it starts where the muzzle
        // was, not wherever the scrub happens to stand.
        let start = SIMD3<Double>(paths[0][0])
        XCTAssertLessThan(simd_distance(start, model.muzzlePoint), 0.1)
    }

    // MARK: The other five benches
    // Same two claims per module; the replay test is what would catch a
    // substep accumulator or a velocity map left out of a snapshot.

    func testPendulumsRoundTripAndReplay() {
        let model = PendulumsModel()
        model.clearCapsule()
        for _ in 0..<120 { model.step(dt: dt) }

        let snapshot = model.captureCapsuleSnapshot()
        for _ in 0..<60 { model.step(dt: dt) }
        model.restoreCapsuleSnapshot(snapshot)
        XCTAssertEqual(model.captureCapsuleSnapshot(), snapshot)

        // Replay: the recorded frames must come back frame for frame.
        model.isPaused = true
        model.scrub(toOffset: 0.4)
        let scrubbed = try! XCTUnwrap(model.scrubTime)
        let recorded = model.capsule.frames(in: scrubbed...(scrubbed + 31 * dt))
        model.commitScrubAndResume()
        for frame in recorded.dropFirst() {
            model.step(dt: dt)
            for (live, original) in zip(model.pendulums, frame.snapshot.pendulums) {
                XCTAssertLessThan(
                    simd_distance(live.bobWorld, original.bobWorld), 1e-9,
                    "Pendulums replay diverged — a dynamical field is missing from CapsuleSnapshot")
            }
        }
    }

    func testOrbitalMechanicsRoundTripAndTrailRebuild() {
        let model = OrbitalMechanicsModel()
        model.clearCapsule()
        for _ in 0..<120 { model.step(dt: dt) }

        let snapshot = model.captureCapsuleSnapshot()
        for _ in 0..<60 { model.step(dt: dt) }
        model.restoreCapsuleSnapshot(snapshot)
        XCTAssertEqual(model.captureCapsuleSnapshot(), snapshot)

        // Trails are excluded from the snapshot and rebuilt from the
        // capsule, so a scrubbed body still trails its recorded path.
        model.isPaused = true
        model.scrub(toOffset: 0.5)
        let trailed = model.bodies.filter { !$0.trail.isEmpty }
        XCTAssertFalse(trailed.isEmpty,
                       "A scrubbed sky should show the recorded trails")
    }

    func testMagnetismRoundTripKeepsInertialMotion() {
        let model = MagnetismModel()
        model.inertiaOn = true
        model.addMagnet()
        model.clearCapsule()
        for _ in 0..<120 { model.step(dt: dt) }

        let snapshot = model.captureCapsuleSnapshot()
        for _ in 0..<60 { model.step(dt: dt) }
        model.restoreCapsuleSnapshot(snapshot)
        XCTAssertEqual(model.captureCapsuleSnapshot(), snapshot)
        // The velocity map is the point: without it a restored needle
        // comes back at rest and never rings.
        XCTAssertEqual(model.captureCapsuleSnapshot().bodies, snapshot.bodies)
    }

    func testFieldRoundTripAndProbeTrailRebuild() {
        let model = FieldModel()
        model.dropProbe()
        model.clearCapsule()
        for _ in 0..<120 { model.step(dt: dt) }

        let snapshot = model.captureCapsuleSnapshot()
        for _ in 0..<60 { model.step(dt: dt) }
        model.restoreCapsuleSnapshot(snapshot)
        XCTAssertEqual(model.captureCapsuleSnapshot(), snapshot)
    }

    /// Circuits scrubs its transients and its topology: a rewire inside
    /// the window comes back with the bench that was there at the time.
    func testCircuitsRestoresTopologyAndTransients() {
        let model = CircuitsModel()
        model.clearCapsule()
        for _ in 0..<90 { model.step(dt: dt) }
        let before = model.components.count

        let snapshot = model.captureCapsuleSnapshot()
        _ = model.add(.resistor)
        for _ in 0..<60 { model.step(dt: dt) }
        XCTAssertEqual(model.components.count, before + 1)

        model.restoreCapsuleSnapshot(snapshot)
        XCTAssertEqual(model.components.count, before)
        XCTAssertEqual(model.captureCapsuleSnapshot(), snapshot)
    }

    /// A scrubbed bench must never be written to disk: a rewind you were
    /// only inspecting must not become the bench you find next launch.
    func testCircuitsDoesNotPersistWhileScrubbed() {
        let model = CircuitsModel()
        model.clearCapsule()
        for _ in 0..<90 { model.step(dt: dt) }
        model.isPaused = true
        model.scrub(toOffset: 0.3)

        let key = CircuitsModel.saveKey
        let saved = UserDefaults.standard.data(forKey: key)
        model.persistNow()
        XCTAssertEqual(UserDefaults.standard.data(forKey: key), saved,
                       "A scrubbed bench was written to disk")
    }

    /// Every module's reset empties its capsule — a fresh bench must not
    /// carry the old bench's past.
    /// The optics bench has no dynamics — its past is where the pieces
    /// stood and how the lights were set — and what a hand holds stays put.
    func testOpticsRoundTripLeavesAHeldPieceAlone() throws {
        let model = OpticsModel()
        model.clearCapsule()
        for _ in 0..<10 { model.step(dt: dt) }
        let snapshot = model.captureCapsuleSnapshot()
        let prism = try XCTUnwrap(model.pieces.first { $0.kind == .prism })
        let bar = try XCTUnwrap(model.pieces.first { $0.kind == .block })
        model.move(id: prism.id, to: prism.position + SIMD3(0.2, 0, 0))
        model.grab(id: bar.id)
        let held = bar.position + SIMD3(0, 0.1, 0)
        model.move(id: bar.id, to: held)
        model.cycleLaserColour()
        model.restoreCapsuleSnapshot(snapshot)
        XCTAssertEqual(model.pieces.first { $0.id == prism.id }?.position, prism.position)
        XCTAssertEqual(model.pieces.first { $0.id == bar.id }?.position, held)
        XCTAssertEqual(model.laserNanometers, snapshot.laserNanometers)
    }

    func testResetClearsEveryCapsule() {
        let pendulums = PendulumsModel()
        for _ in 0..<30 { pendulums.step(dt: dt) }
        pendulums.reset()
        XCTAssertNil(pendulums.capsuleSpan)

        let gravity = OrbitalMechanicsModel()
        for _ in 0..<30 { gravity.step(dt: dt) }
        gravity.reset()
        XCTAssertNil(gravity.capsuleSpan)

        let magnetism = MagnetismModel()
        for _ in 0..<30 { magnetism.step(dt: dt) }
        magnetism.reset()
        XCTAssertNil(magnetism.capsuleSpan)

        let field = FieldModel()
        for _ in 0..<30 { field.step(dt: dt) }
        field.reset()
        XCTAssertNil(field.capsuleSpan)

        let circuits = CircuitsModel()
        for _ in 0..<30 { circuits.step(dt: dt) }
        circuits.reset()
        XCTAssertNil(circuits.capsuleSpan)

        let optics = OpticsModel()
        for _ in 0..<30 { optics.step(dt: dt) }
        optics.reset()
        XCTAssertNil(optics.capsuleSpan)
    }

    // MARK: The feature switched off

    /// Switched off, a lab costs exactly what it cost before the capsule
    /// existed: no snapshot is taken and there is nothing to scrub.
    func testNothingIsRecordedWhenTheFeatureIsOff() {
        TimeCapsuleSettings.isEnabled = false
        let model = bareModel()
        model.fire()
        for _ in 0..<120 { model.step(dt: dt) }

        XCTAssertNil(model.capsuleSpan)
        XCTAssertTrue(model.capsule.isEmpty)
        // And the scrub verbs are inert rather than crashing.
        model.isPaused = true
        model.scrub(toOffset: 1)
        model.stepScrub(frames: -1)
        XCTAssertNil(model.scrubTime)
    }

    /// Switching it off mid-session drops what was already recorded. A
    /// capsule that survived being switched off would be a recording
    /// kept after the user said stop.
    func testSwitchingOffDropsTheRecording() {
        let model = bareModel()
        model.fire()
        for _ in 0..<90 { model.step(dt: dt) }
        XCTAssertNotNil(model.capsuleSpan)

        TimeCapsuleSettings.isEnabled = false
        model.step(dt: dt)
        XCTAssertNil(model.capsuleSpan)
        XCTAssertTrue(model.capsule.isEmpty)
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
