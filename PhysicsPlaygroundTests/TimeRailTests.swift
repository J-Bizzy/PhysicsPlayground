//
//  TimeRailTests.swift
//  PhysicsPlaygroundTests
//
//  The Time Rail, driven the only way this project can drive a spatial
//  control: real entities, `handleTap`/`handleDrag` invoked directly
//  (no automation can synthesise a pinch — docs/ON_DEVICE_TESTS.md).
//
//  These tests go through the REAL descriptor from `ModuleCatalog`, so
//  they also prove the wiring: a rail built for the kinematics module
//  scrubs the kinematics model, not a stand-in.
//

import XCTest
import PhysicsCore
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class TimeRailTests: XCTestCase {

    private let dt = 1.0 / 90.0

    /// The real kinematics descriptor, with its model paused on ~2 s of
    /// recording — the state the rail exists for.
    override func tearDown() {
        TimeCapsuleSettings.isEnabled = false
        super.tearDown()
    }

    private func makeRecordedModule() -> (ModuleDescriptor, KinematicsModel, AppModel) {
        let appModel = AppModel()
        // AFTER `AppModel()`, never before: constructing it builds
        // `AppSettings`, which pushes the stored answer (off) into the
        // recording gate. Enabling first would be silently undone.
        TimeCapsuleSettings.isEnabled = true
        let module = ModuleCatalog.all(appModel: appModel)
            .first { $0.id == KinematicsModule.id }!
        let model = appModel.kinematicsModel
        model.roomWalls = []
        model.roomBounds = RoomBox(center: SIMD3(0, 50, 0),
                                   halfExtents: SIMD3(100, 50, 100))
        model.clearCapsule()
        for _ in 0..<180 { model.step(dt: dt) }
        model.isPaused = true
        return (module, model, appModel)
    }

    /// Run the rail forward until its fold and draw eases settle.
    private func settle(_ rail: TimeRail) {
        for _ in 0..<60 {
            rail.update(dt: 1.0 / 30.0, viewer: [0, 1.6, 1], placement: .zero)
        }
    }

    /// The reel arrives closed; a pinch draws the tape out. Most tests
    /// want the rail operable, which is two steps now, not one.
    private func settleOpen(_ rail: TimeRail) {
        settle(rail)
        rail.setOpen(true)
        settle(rail)
    }

    private func reel(_ rail: TimeRail) throws -> Entity {
        try XCTUnwrap(rail.root.findEntity(named: "time-reel"))
    }

    private func plate(_ rail: TimeRail, _ id: String) throws -> Entity {
        try XCTUnwrap(
            rail.root.findEntity(named: "action-\(id)"),
            "No plate was built for \(id).")
    }

    /// The rail stays folded while the module runs, and comes out when
    /// the module pauses with a recording worth scrubbing.
    func testRailAppearsOnlyWhilePausedWithARecording() {
        let (module, model, _) = makeRecordedModule()
        model.isPaused = false

        let rail = TimeRail(module: module)
        settle(rail)
        XCTAssertFalse(rail.isVisible)

        model.isPaused = true
        settle(rail)
        XCTAssertTrue(rail.isVisible)

        // …and never over an inert capsule: a module that has not
        // adopted the recording contract shows no rail at all, however
        // long it is paused.
        model.clearCapsule()
        settle(rail)
        XCTAssertFalse(rail.isVisible)
    }

    /// The descriptor wiring, end to end: scrubbing through the catalog's
    /// own closures moves the kinematics model.
    func testDescriptorScrubReachesTheModel() {
        let (module, model, _) = makeRecordedModule()
        module.timeScrub.scrub(1.0)
        let scrubbed = try! XCTUnwrap(model.scrubTime)
        let span = try! XCTUnwrap(model.capsuleSpan)
        XCTAssertEqual(span.upperBound - scrubbed, 1.0, accuracy: dt)

        module.timeScrub.resume()
        XCTAssertNil(model.scrubTime)
        XCTAssertFalse(model.isPaused)
    }

    /// The pause petal's closure resumes from the scrubbed instant —
    /// truncating the rejected future — rather than merely unfreezing.
    func testTogglePauseResumesFromScrubbedInstant() {
        let (module, model, _) = makeRecordedModule()
        module.timeScrub.scrub(1.0)
        let scrubbed = try! XCTUnwrap(model.scrubTime)

        module.togglePause()
        XCTAssertFalse(model.isPaused)
        let span = try! XCTUnwrap(model.capsuleSpan)
        XCTAssertEqual(span.upperBound, scrubbed, accuracy: 1e-12)
    }

    /// A tap on a frame-step plate moves the model exactly one recorded
    /// physics tick.
    func testFrameStepPlatesStepTheModel() throws {
        let (module, model, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        settleOpen(rail)

        XCTAssertTrue(rail.handleTap(try plate(rail, "back")))
        let first = try XCTUnwrap(model.scrubTime)
        XCTAssertTrue(rail.handleTap(try plate(rail, "back")))
        let second = try XCTUnwrap(model.scrubTime)
        XCTAssertEqual(first - second, dt, accuracy: 1e-9)

        XCTAssertTrue(rail.handleTap(try plate(rail, "ahead")))
        XCTAssertEqual(try XCTUnwrap(model.scrubTime), first, accuracy: 1e-12)
    }

    /// The resume plate un-pauses from the frozen instant.
    func testResumePlateResumes() throws {
        let (module, model, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        settleOpen(rail)
        module.timeScrub.scrub(0.5)

        XCTAssertTrue(rail.handleTap(try plate(rail, "resume")))
        XCTAssertFalse(model.isPaused)
        XCTAssertNil(model.scrubTime)
    }

    /// A drag along the rail scrubs: hand at the far-left end of the rail
    /// reaches the oldest recorded frame, at the right end the newest.
    /// The hand arrives in world space; the rail converts.
    func testDragAlongRailScrubs() throws {
        let (module, model, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        settleOpen(rail)
        // The drag lands on the track itself, as a pinch would — `owns`
        // resolves an entity to the rail it belongs to by walking UP.
        let trackEntity = try XCTUnwrap(rail.root.findEntity(named: "Time"))

        let center = SIMD3<Double>(SIMD3<Float>(rail.root.position))
        // Left end: deep past — clamped to the oldest recorded frame.
        XCTAssertTrue(rail.handleDrag(
            entity: trackEntity, handWorld: center + SIMD3(-0.17, 0, 0)))
        let span = try XCTUnwrap(model.capsuleSpan)
        XCTAssertEqual(try XCTUnwrap(model.scrubTime), span.lowerBound,
                       accuracy: 1e-9)

        // Right end: now.
        XCTAssertTrue(rail.handleDrag(
            entity: trackEntity, handWorld: center + SIMD3(0.17, 0, 0)))
        XCTAssertEqual(try XCTUnwrap(model.scrubTime), span.upperBound,
                       accuracy: 1e-9)
        rail.endDrag()
    }

    /// A folded rail consumes nothing — taps and drags fall through to
    /// the room.
    func testFoldedRailConsumesNothing() throws {
        let (module, model, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        settleOpen(rail)
        let back = try plate(rail, "back")

        model.isPaused = false
        settle(rail)
        XCTAssertFalse(rail.isVisible)
        XCTAssertFalse(rail.handleTap(back))
        XCTAssertFalse(rail.handleDrag(entity: rail.root, handWorld: .zero))
    }

    // MARK: The reel — the instrument is closed until it is asked for

    /// A pause puts the REEL on screen, not the rail. This is the whole
    /// point of the object: the always-on rail was a feature permanently
    /// occupying the room, and the fix was to give the capability a thing
    /// that stays wound until pinched.
    func testPauseShowsTheReelAndNotTheRail() throws {
        let (module, _, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        settle(rail)

        XCTAssertTrue(rail.isVisible, "The reel should arrive with the pause")
        XCTAssertFalse(rail.isOpen)
        XCTAssertFalse(rail.isDrawnOut, "The tape drew itself out unasked")
        // The track is present but not operable, and the plates cannot be
        // pressed through a wound reel.
        XCTAssertFalse(rail.handleTap(try plate(rail, "back")))
    }

    /// Pinching the reel draws the tape out; pinching it again winds it
    /// back in. A tap on its nameplate is a tap on the reel.
    func testPinchingTheReelDrawsTheTapeOut() throws {
        let (module, _, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        settle(rail)

        XCTAssertTrue(rail.handleTap(try reel(rail)))
        XCTAssertTrue(rail.isOpen)
        settle(rail)
        XCTAssertTrue(rail.isDrawnOut)
        XCTAssertTrue(rail.handleTap(try plate(rail, "back")),
                      "A drawn-out rail should take its plates")

        XCTAssertTrue(rail.handleTap(try reel(rail)))
        XCTAssertFalse(rail.isOpen)
        settle(rail)
        XCTAssertFalse(rail.isDrawnOut)
    }

    /// The rail is not draggable until the tape is all the way out —
    /// mid-draw its root is still sliding, and a drag against a moving
    /// mapping would write a value the bead never showed.
    func testRailIsNotDraggableMidDraw() throws {
        let (module, model, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        settle(rail)
        let trackEntity = try XCTUnwrap(rail.root.findEntity(named: "Time"))
        let hand = SIMD3<Double>(SIMD3<Float>(rail.root.position))

        rail.setOpen(true)
        // One frame of the draw: begun, nowhere near finished.
        rail.update(dt: 1.0 / 90.0, viewer: [0, 1.6, 1], placement: .zero)
        XCTAssertFalse(rail.isDrawnOut)
        XCTAssertFalse(rail.handleDrag(entity: trackEntity, handWorld: hand))
        XCTAssertNil(model.scrubTime)

        settle(rail)
        XCTAssertTrue(rail.handleDrag(entity: trackEntity, handWorld: hand))
        rail.endDrag()
    }

    /// The tape winds itself back in when the instrument leaves, so the
    /// next pause opens on a reel rather than on whatever the last one
    /// was left showing.
    func testResumingWindsTheTapeBackIn() throws {
        let (module, model, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        settleOpen(rail)
        XCTAssertTrue(rail.isOpen)

        model.isPaused = false
        settle(rail)
        XCTAssertFalse(rail.isVisible)
        XCTAssertFalse(rail.isOpen)

        model.isPaused = true
        settle(rail)
        XCTAssertTrue(rail.isVisible)
        XCTAssertFalse(rail.isOpen, "The next pause should open on the reel")
    }

    /// With the capsule switched off, a pause is just a pause: no reel,
    /// no rail, nothing new in the room at all.
    func testNoReelWhenTheFeatureIsOff() {
        let appModel = AppModel()
        TimeCapsuleSettings.isEnabled = false
        let module = ModuleCatalog.all(appModel: appModel)
            .first { $0.id == KinematicsModule.id }!
        let model = appModel.kinematicsModel
        model.roomWalls = []
        model.roomBounds = RoomBox(center: SIMD3(0, 50, 0),
                                   halfExtents: SIMD3(100, 50, 100))
        for _ in 0..<180 { model.step(dt: dt) }
        model.isPaused = true

        let rail = TimeRail(module: module)
        settle(rail)
        XCTAssertFalse(rail.isVisible,
                       "The reel appeared for a feature that is switched off")
    }

    /// The reel arrives still turning — recording stopped at the instant
    /// of the pause, so a reel already at rest would be one that had
    /// never been running. It coasts down to a stop on its own.
    func testTheReelCoastsToAStopOnArrival() throws {
        let (module, _, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        let spindle = try XCTUnwrap(reel(rail).children.first)

        // A few frames in, it has turned.
        for _ in 0..<4 {
            rail.update(dt: 1.0 / 90.0, viewer: [0, 1.6, 1], placement: .zero)
        }
        let early = spindle.orientation.angle
        XCTAssertGreaterThan(early, 0.01, "The reel arrived already at rest")

        // …and then stops, rather than turning for ever.
        settle(rail)
        let settled = spindle.orientation.angle
        settle(rail)
        XCTAssertEqual(spindle.orientation.angle, settled, accuracy: 1e-5,
                       "The reel never stopped coasting")
    }

    /// Reduce Motion suppresses the coast, which is decoration. The DRAW
    /// is not suppressed — it answers a pinch, and a control that does
    /// not answer reads as broken.
    func testReduceMotionStillsTheCoastButNotTheDraw() throws {
        let (module, _, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        rail.stillness = true
        let spindle = try XCTUnwrap(reel(rail).children.first)

        for _ in 0..<4 {
            rail.update(dt: 1.0 / 90.0, viewer: [0, 1.6, 1], placement: .zero)
        }
        XCTAssertEqual(spindle.orientation.angle, 0, accuracy: 1e-6,
                       "The reel coasted under Reduce Motion")

        settle(rail)
        rail.setOpen(true)
        settle(rail)
        XCTAssertTrue(rail.isDrawnOut, "Reduce Motion swallowed the draw")
    }

    /// Drawing the tape out TURNS the reel, by arc ÷ radius — a third of
    /// a metre off a 38 mm spool is very nearly a turn and a half. A reel
    /// that stayed still while its tape ran out would be the one part of
    /// this instrument that lied.
    func testDrawingTheTapeTurnsTheReel() throws {
        let (module, _, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        rail.stillness = true          // isolate the draw from the coast
        settle(rail)
        let spindle = try XCTUnwrap(reel(rail).children.first)
        XCTAssertEqual(spindle.orientation.angle, 0, accuracy: 1e-6)

        rail.setOpen(true)
        settle(rail)
        // Compared as a QUATERNION, not as `.angle`. A third of a metre
        // over a 38 mm spool is 8.95 rad — more than a full turn — and
        // `simd_quatf.angle` wraps into [0, π], so it reads that back as
        // 3.62 and a naive assertion fails a reel that is turning
        // exactly right. (It did.)
        assertTurned(spindle, by: -TimeRail.railLength / TimeRail.tapeRadius,
                     "The reel did not turn by the tape it gave up")

        // Winding in returns it exactly, so open/close leaves no drift.
        rail.setOpen(false)
        settle(rail)
        assertTurned(spindle, by: 0, "Winding in left the reel adrift")
    }

    /// Asserts a spindle carries a rotation of `angle` about Z. Two
    /// quaternions describe the same rotation when |q₁ · q₂| is 1, which
    /// is wrap-proof in a way comparing angles is not.
    private func assertTurned(_ entity: Entity, by angle: Float,
                              _ message: String,
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        let expected = simd_quatf(angle: angle, axis: [0, 0, 1])
        let alignment = abs(simd_dot(entity.orientation.vector, expected.vector))
        XCTAssertEqual(alignment, 1, accuracy: 1e-3, message,
                       file: file, line: line)
    }

    /// The closed reel is a READOUT, not just a lid: it turns with the
    /// scrub, so how far back you are is legible from the object itself.
    func testTheReelTurnsWithTheScrub() throws {
        let (module, _, _) = makeRecordedModule()
        let rail = TimeRail(module: module)
        settleOpen(rail)
        // The SPINDLE turns; the mount it hangs on does not, or the
        // nameplate would roll onto its side with it (it did, once).
        let mount = try reel(rail)
        let spindle = try XCTUnwrap(mount.children.first)
        let wound = spindle.orientation.angle
        let plateUpright = try XCTUnwrap(
            mount.children.first { $0 !== spindle }).orientation

        module.timeScrub.scrub(1.0)
        settle(rail)
        XCTAssertNotEqual(spindle.orientation.angle, wound, accuracy: 0.05,
                          "The reel did not turn as the tape ran out")
        XCTAssertEqual(mount.orientation.angle, 0, accuracy: 1e-6,
                       "The reel's mount turned with it")
        XCTAssertEqual(
            try XCTUnwrap(mount.children.first { $0 !== spindle }).orientation.angle,
            plateUpright.angle, accuracy: 1e-6,
            "The nameplate turned with the reel")
    }

    /// ALL SIX modules answer the scrub contract — the rail is shell
    /// chrome, and a lab where pause did nothing but freeze would be the
    /// one place the feature was missing. A fresh model has recorded
    /// nothing, so every span starts nil and the rail stays folded.
    func testEveryModuleAnswersTheScrubContract() {
        let appModel = AppModel()
        let modules = ModuleCatalog.all(appModel: appModel)
        XCTAssertEqual(modules.count, 6)
        for module in modules {
            XCTAssertNil(module.timeScrub.span(),
                         "\(module.id) reports a recording before anything ran")
            XCTAssertNil(module.timeScrub.scrubTime())
            // Scrubbing an empty capsule is a no-op, not a crash and not
            // a fabricated instant.
            module.timeScrub.scrub(1)
            module.timeScrub.stepFrames(-1)
            XCTAssertNil(module.timeScrub.scrubTime(),
                         "\(module.id) invented a scrub instant with nothing recorded")
        }
    }

    /// The rail's unit is seconds of the WEARER's life, on every bench.
    /// Gravity Lab is the one that could get this wrong — its own clock
    /// runs in days at up to 100× — so a second of recording there must
    /// still be a second.
    func testCapsuleClockIsWallClockSecondsEverywhere() {
        let appModel = AppModel()
        TimeCapsuleSettings.isEnabled = true      // after AppModel, per above
        let gravity = appModel.gravityLabModel
        gravity.clearCapsule()
        gravity.timeScale = 100
        for _ in 0..<90 { gravity.step(dt: dt) }
        let span = try! XCTUnwrap(gravity.capsuleSpan)
        XCTAssertEqual(span.upperBound - span.lowerBound, 89 * dt, accuracy: 1e-9,
                       "Gravity Lab's capsule clock is not wall-clock seconds")
    }
}
