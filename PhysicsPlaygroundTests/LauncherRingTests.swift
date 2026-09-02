//
//  LauncherRingTests.swift
//  PhysicsPlaygroundTests
//
//  The launcher's ring folds by tap (2026-09-01). Until then
//  `KinematicsSpaceView.syncBloom` passed `revealTarget: 1` every frame,
//  so the launcher was the one object in the app whose ring never closed
//  — Fire, Balls, Clear and the speed grip stood over it permanently,
//  against the design system's "unfolded by tap, never gaze".
//
//  Two claims. The ROUTING is a pure static over entity names, in the
//  `CircuitsSpaceView.resolveGrab` pattern, so a headset is not needed to
//  prove which tap opens, which folds, and which leaves the ring alone.
//  The FOLD is real: a `Bloom` at reveal 0 offers no petal and no grip,
//  so the only way to fire from the ring or pull the speed bead is to
//  have opened it — which is the whole point, and the reason aiming was
//  deliberately left OUT of the ring (the aim bead is the renderer's own
//  sibling entity and works folded).
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class LauncherRingTests: XCTestCase {

    // MARK: Routing

    func testTheLauncherTogglesItsRing() throws {
        let renderer = KinematicsRenderer()
        let launcher = try XCTUnwrap(
            renderer.root.findEntity(named: KinematicsRenderer.launcherName))

        XCTAssertTrue(KinematicsSpaceView.launcherRingOpen(afterTapOn: launcher, wasOpen: false),
                      "a tap on the closed launcher opens its ring")
        XCTAssertFalse(KinematicsSpaceView.launcherRingOpen(afterTapOn: launcher, wasOpen: true),
                       "a second tap folds it, in place")
    }

    /// The bead is the launcher's own verb: aiming must never fold the
    /// ring the wearer just opened, and must never open it either.
    func testTheAimBeadLeavesTheRingAlone() throws {
        let renderer = KinematicsRenderer()
        let bead = try XCTUnwrap(
            renderer.root.findEntity(named: KinematicsRenderer.aimBeadName))

        XCTAssertFalse(KinematicsSpaceView.launcherRingOpen(afterTapOn: bead, wasOpen: false))
        XCTAssertTrue(KinematicsSpaceView.launcherRingOpen(afterTapOn: bead, wasOpen: true))
    }

    /// A ball, a hoop, empty space — anything else folds the ring, the
    /// grammar every other module's ring answers to.
    func testAnythingElseFoldsTheRing() {
        let ball = Entity()
        ball.name = UUID().uuidString
        let blank = Entity()

        XCTAssertFalse(KinematicsSpaceView.launcherRingOpen(afterTapOn: ball, wasOpen: true))
        XCTAssertFalse(KinematicsSpaceView.launcherRingOpen(afterTapOn: blank, wasOpen: true))
        XCTAssertFalse(KinematicsSpaceView.launcherRingOpen(afterTapOn: ball, wasOpen: false))
    }

    /// The routing walks the parent chain, so a tap on a child of the
    /// launcher (a decal, a shadow) is a tap on the launcher.
    func testAChildOfTheLauncherCountsAsTheLauncher() throws {
        let renderer = KinematicsRenderer()
        let launcher = try XCTUnwrap(
            renderer.root.findEntity(named: KinematicsRenderer.launcherName))
        let child = Entity()
        launcher.addChild(child)

        XCTAssertTrue(KinematicsSpaceView.launcherRingOpen(afterTapOn: child, wasOpen: false))
    }

    // MARK: Hoops have rings too (2026-09-01)

    /// The renderer names a hoop's tube with the ring's id; a tap on it
    /// or on anything under it resolves to that hoop, and nothing else
    /// does.
    func testATapOnAHoopResolvesToThatHoop() {
        let model = KinematicsModel()
        model.clearFlights()
        let id = model.addRing(at: SIMD3(0, 1, -1))!
        let tube = Entity()
        tube.name = id.uuidString
        let child = Entity()
        tube.addChild(child)
        let stranger = Entity()
        stranger.name = UUID().uuidString

        XCTAssertEqual(KinematicsSpaceView.hoopID(under: tube, rings: model.rings), id)
        XCTAssertEqual(KinematicsSpaceView.hoopID(under: child, rings: model.rings), id)
        XCTAssertNil(KinematicsSpaceView.hoopID(under: stranger, rings: model.rings),
                     "a UUID-named entity that is not a hoop is not a hoop")
        model.removeRing(id: id)
        XCTAssertNil(KinematicsSpaceView.hoopID(under: tube, rings: model.rings),
                     "a deleted hoop's tube no longer resolves")
    }

    // MARK: The fold is real

    /// Folded, the ring offers nothing: no petal takes a tap and the
    /// grip refuses a pull. Open, both answer. This is what makes the
    /// tap load-bearing rather than cosmetic — and why the aim bead was
    /// kept OUT of the ring, since aiming must work with the ring shut.
    func testAFoldedRingOffersNoPetalAndNoGrip() throws {
        var fired = 0
        var speed = 5.0
        let bloom = Bloom()
        bloom.retarget(
            "launcher",
            petals: [.init(name: "Fire", symbol: "paperplane.fill", tint: .white) { fired += 1 }],
            grip: .init(name: "Launch speed", range: 0.5...15,
                        read: { speed }, write: { speed = $0 },
                        format: { "\($0)" }, radius: { 0.10 }))
        let fire = try XCTUnwrap(bloom.root.children.first { $0.name == "bloom-Fire" })
        let grip = try XCTUnwrap(bloom.root.children.first { $0.name == "bloom-grip" })

        // Folded: the state `revealTarget: 0` leaves it in.
        for _ in 0..<40 {
            bloom.update(anchor: .zero, viewer: [0, 0, 1], revealTarget: 0, dt: 1.0 / 90.0)
        }
        XCTAssertFalse(bloom.handleTap(fire), "a folded ring must not fire")
        XCTAssertFalse(bloom.beginGrip(grip, hand: .zero), "a folded ring must not hand out its grip")
        XCTAssertEqual(fired, 0)

        // Open: the state one tap on the launcher puts it in.
        for _ in 0..<40 {
            bloom.update(anchor: .zero, viewer: [0, 0, 1], revealTarget: 1, dt: 1.0 / 90.0)
        }
        XCTAssertTrue(bloom.handleTap(fire), "the open ring's petal answers a tap")
        XCTAssertEqual(fired, 1)
        XCTAssertTrue(bloom.beginGrip(grip, hand: .zero), "the open ring hands out its grip")
        bloom.endGrip()
    }
}
