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
    private func makeRecordedModule() -> (ModuleDescriptor, KinematicsModel, AppModel) {
        let appModel = AppModel()
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

    /// Run the rail forward until its fold ease settles.
    private func settle(_ rail: TimeRail) {
        for _ in 0..<40 {
            rail.update(dt: 1.0 / 30.0, viewer: [0, 1.6, 1], placement: .zero)
        }
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
        settle(rail)

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
        settle(rail)
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
        settle(rail)
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
        settle(rail)
        let back = try plate(rail, "back")

        model.isPaused = false
        settle(rail)
        XCTAssertFalse(rail.isVisible)
        XCTAssertFalse(rail.handleTap(back))
        XCTAssertFalse(rail.handleDrag(entity: rail.root, handWorld: .zero))
    }

    /// Every module's descriptor carries a scrub contract; the five that
    /// have not adopted the capsule yet are inert (nil span), so the rail
    /// never appears over them.
    func testUnadoptedModulesAreInert() {
        let appModel = AppModel()
        for module in ModuleCatalog.all(appModel: appModel)
        where module.id != KinematicsModule.id {
            XCTAssertNil(module.timeScrub.span(),
                         "\(module.id) reports a span with no adoption")
            // No-ops must actually be no-ops.
            module.timeScrub.scrub(1)
            module.timeScrub.stepFrames(-1)
            XCTAssertNil(module.timeScrub.scrubTime())
        }
    }
}
