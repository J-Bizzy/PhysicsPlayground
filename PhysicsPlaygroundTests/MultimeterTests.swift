//
//  MultimeterTests.swift
//  Physics Playground — app tests
//
//  The bench meter. Nothing automated can pinch a RealityKit entity, so
//  these call the handlers directly: what they can check is that every
//  precondition for a hand reaching the instrument is in place.
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class MultimeterTests: XCTestCase {

    private static let home = SIMD3<Float>(-0.6, 1.2, -0.9)

    private func meter() -> Multimeter {
        Multimeter(accent: .systemGreen, anchor: Self.home)
    }

    /// Finds a named descendant, the way a gesture's hit-test result
    /// arrives — as some entity somewhere under the root.
    private func find(_ name: String, under entity: Entity) -> Entity? {
        if entity.name == name { return entity }
        for child in entity.children {
            if let hit = find(name, under: child) { return hit }
        }
        return nil
    }

    // MARK: Move

    /// The case is a hit-testable object at all. Three components, and
    /// missing any one of them means a gaze slides straight over it.
    func testTheCaseCanBeHitTested() throws {
        let body = try XCTUnwrap(find(Multimeter.bodyName, under: meter().root),
                                 "the case has no name for a drag to match")
        XCTAssertNotNil(body.components[InputTargetComponent.self],
                        "the case takes no input")
        XCTAssertNotNil(body.components[CollisionComponent.self],
                        "the case has no collider — nothing to grab")
        XCTAssertNotNil(body.components[HoverEffectComponent.self],
                        "the case gives no hover feedback, so nothing says "
                        + "it can be picked up")
    }

    /// The collider is the case and not a box around it: this instrument
    /// stands among terminals a centimetre apart.
    func testTheCaseColliderIsTheCase() throws {
        let body = try XCTUnwrap(find(Multimeter.bodyName, under: meter().root))
        let collision = try XCTUnwrap(body.components[CollisionComponent.self])
        let shape = try XCTUnwrap(collision.shapes.first)
        let extents = shape.bounds.extents
        // The real body is 86 × 168 × 32 mm.
        XCTAssertEqual(extents.x, 0.086, accuracy: 0.004)
        XCTAssertEqual(extents.y, 0.168, accuracy: 0.004)
        XCTAssertEqual(extents.z, 0.032, accuracy: 0.004)
    }

    /// The case answers to `isBody`; the dial and the probes do not, or a
    /// drag on the dial would slide the meter and carrying a probe would
    /// carry the meter.
    func testOnlyTheCaseIsTheHandle() throws {
        let meter = meter()
        let body = try XCTUnwrap(find(Multimeter.bodyName, under: meter.root))
        XCTAssertTrue(meter.isBody(body))

        let dial = try XCTUnwrap(find("meter-dial", under: meter.root))
        XCTAssertFalse(meter.isBody(dial), "the dial is a control, not a handle")

        for name in ["meter-probe-red", "meter-probe-black"] {
            let probe = try XCTUnwrap(find(name, under: meter.root))
            XCTAssertFalse(meter.isBody(probe), "\(name) is not the handle")
        }
    }

    /// A placed meter stays placed across a frame. It reads the case's
    /// world position, not `root.position`: `root` stays at identity.
    func testAPlacedMeterSurvivesTheRenderLoop() throws {
        let meter = meter()
        let model = CircuitsModel()
        let body = try XCTUnwrap(find(Multimeter.bodyName, under: meter.root))
        let moved = Self.home + SIMD3(0.35, -0.10, 0.20)

        meter.place(at: moved)
        for _ in 0..<12 {
            meter.update(viewer: SIMD3(0, 1.5, 0), model: model)
        }

        XCTAssertEqual(meter.anchor, moved)
        XCTAssertEqual(simd_distance(body.position(relativeTo: nil), moved), 0,
                       accuracy: 1e-5,
                       "the render loop moved the meter back to where the "
                       + "view thought it should be")
    }

    // MARK: Reset

    /// Reset puts the meter back on the shelf: the meter is a view object,
    /// so a model reset alone cannot reach it, and `ResetCoverageTests`
    /// cannot see a `Set` on a view object.
    func testAResetPutsTheMeterBackInTheRack() throws {
        let meter = meter()
        let model = CircuitsModel()
        let carriedTo = Self.home + SIMD3(0.4, 0.2, 0.3)

        // Out of the rack, into a hand, with a probe placed on the bench.
        meter.root.isEnabled = true
        meter.place(at: carriedTo)
        meter.update(viewer: SIMD3(0, 1.5, 0), model: model, resetNonce: 0)
        meter.moveProbe(.red, local: Self.home + SIMD3(0.10, 0, -0.04),
                        bench: SIMD3(0, 1.2, -0.9), model: model)
        meter.update(viewer: SIMD3(0, 1.5, 0), model: model, resetNonce: 0)
        XCTAssertEqual(meter.anchor, carriedTo, "the meter never left the rack")

        // The shell bumps the nonce; the next frame is what notices.
        meter.update(viewer: SIMD3(0, 1.5, 0), model: model, resetNonce: 1)

        XCTAssertFalse(meter.root.isEnabled,
                       "the meter is still drawn after a reset — the rack "
                       + "slot's miniature and the real instrument are both "
                       + "in the room")
        XCTAssertEqual(meter.anchor, Self.home,
                       "the case stayed where a hand carried it")
        let jack = try XCTUnwrap(meter.probeTip[.red])
        XCTAssertLessThan(jack.y, Self.home.y,
                          "the red probe is still out on the bench rather "
                          + "than hanging in its holster")
    }

    /// The first frame must not stow a meter somebody just pulled out.
    /// `seenResetNonce` starts nil for exactly this reason — the app's
    /// count is not zero after the user has reset any lab this session.
    func testTheFirstFrameAdoptsTheNonceRatherThanStowing() {
        let meter = meter()
        let model = CircuitsModel()

        meter.root.isEnabled = true
        meter.place(at: Self.home + SIMD3(0.4, 0, 0))
        meter.update(viewer: SIMD3(0, 1.5, 0), model: model, resetNonce: 7)

        XCTAssertTrue(meter.root.isEnabled,
                      "the meter stowed itself on its first frame because "
                      + "the app's reset count happened not to be zero")
    }

    /// A reset the meter has already seen does not stow it again — so
    /// pulling the meter out after a reset leaves it out.
    func testTheSameNonceStowsOnlyOnce() {
        let meter = meter()
        let model = CircuitsModel()

        meter.update(viewer: SIMD3(0, 1.5, 0), model: model, resetNonce: 0)
        meter.update(viewer: SIMD3(0, 1.5, 0), model: model, resetNonce: 1)

        // Pulled out again, after the reset.
        meter.root.isEnabled = true
        meter.place(at: Self.home + SIMD3(0.4, 0, 0))
        for _ in 0..<6 {
            meter.update(viewer: SIMD3(0, 1.5, 0), model: model, resetNonce: 1)
        }

        XCTAssertTrue(meter.root.isEnabled,
                      "the meter re-stows every frame after a reset, so it "
                      + "cannot be picked up again")
    }

    /// Moving the meter does not move a placed probe.
    func testMovingTheMeterLeavesAPlacedProbeAlone() throws {
        let meter = meter()
        let model = CircuitsModel()
        let probe = try XCTUnwrap(find("meter-probe-black", under: meter.root))

        meter.update(viewer: SIMD3(0, 1.5, 0.6), model: model)
        meter.moveProbe(.black, local: Self.home + SIMD3(0.10, 0, -0.04),
                        bench: SIMD3(0, 1.2, -0.9), model: model)
        meter.update(viewer: SIMD3(0, 1.5, 0.6), model: model)
        let placed = probe.position(relativeTo: nil)

        meter.place(at: Self.home + SIMD3(-0.4, 0.25, 0.3))
        meter.update(viewer: SIMD3(0, 1.5, 0.6), model: model)

        XCTAssertEqual(simd_distance(probe.position(relativeTo: nil), placed), 0,
                       accuracy: 1e-5,
                       "carrying the meter dragged a placed probe with it")
    }

    /// A probe latched onto a terminal rides it when the circuit turns on
    /// its stage (2026-10-18) — it used to hang where the terminal had been.
    func testALatchedProbeRidesItsTerminalWhenTheCircuitTurns() throws {
        let meter = meter()
        meter.benchToRoom = { SIMD3<Float>($0) }
        let model = CircuitsModel()
        let terminal = CircuitsModel.Terminal(componentID: model.components[0].id, end: 1)
        let point = try XCTUnwrap(model.position(of: terminal))
        meter.update(viewer: nil, model: model)
        meter.moveProbe(.red, local: SIMD3<Float>(point), bench: point, model: model)
        XCTAssertEqual(model.probeA, terminal)
        meter.update(viewer: nil, model: model)

        XCTAssertTrue(model.spinCircuit(by: .pi / 2))
        meter.update(viewer: nil, model: model)
        let moved = try XCTUnwrap(model.position(of: terminal))
        let tip = try XCTUnwrap(meter.probeTip[.red])
        XCTAssertLessThan(simd_distance(tip, SIMD3<Float>(moved)), 1e-5)
    }

    /// And the lead still reaches: it is drawn jack-to-tip and scaled to
    /// span the gap, so its length is the assertion.
    func testTheLeadStretchesWhenTheMeterMovesAway() throws {
        let meter = meter()
        let model = CircuitsModel()

        meter.update(viewer: SIMD3(0, 1.5, 0.6), model: model)
        meter.moveProbe(.red, local: Self.home + SIMD3(0.10, 0, -0.04),
                        bench: SIMD3(0, 1.2, -0.9), model: model)
        meter.update(viewer: SIMD3(0, 1.5, 0.6), model: model)
        let near = simd_distance(meter.probeTip[.red]!, meter.anchor)

        meter.place(at: Self.home + SIMD3(-0.5, 0, 0))
        meter.update(viewer: SIMD3(0, 1.5, 0.6), model: model)
        let far = simd_distance(meter.probeTip[.red]!, meter.anchor)

        XCTAssertGreaterThan(far, near + 0.3,
                             "the gap the lead has to span did not open up")
    }

    // MARK: The probes hold still

    /// A placed probe does not move when the viewer does: the meter turns
    /// to face whoever is looking, and the probes were once children of the
    /// entity that turn applied to. Asked of the entity, not `probeTip` —
    /// the stored tip is a coordinate in a frame that was itself rotating.
    func testAPlacedProbeIgnoresTheViewer() throws {
        let meter = meter()
        let model = CircuitsModel()
        let probe = try XCTUnwrap(find("meter-probe-red", under: meter.root))

        meter.update(viewer: SIMD3(0, 1.5, 0.6), model: model)
        meter.moveProbe(.red, local: SIMD3(0.08, 0.02, -0.05),
                        bench: SIMD3(0, 1.2, -0.9), model: model)
        meter.update(viewer: SIMD3(0, 1.5, 0.6), model: model)
        let placed = probe.position(relativeTo: nil)

        for angle in stride(from: 0.0, to: 2 * Double.pi, by: 0.4) {
            meter.update(
                viewer: Self.home + SIMD3(Float(cos(angle)), 0.3, Float(sin(angle))),
                model: model)
            XCTAssertEqual(
                simd_distance(probe.position(relativeTo: nil), placed), 0,
                accuracy: 1e-5,
                "the red probe rode the case's facing round the bench "
                + "(viewer at \(angle) rad)")
        }
    }

    /// An untouched probe still hangs off the instrument: a holster is part
    /// of the case.
    func testAParkedProbeFollowsTheCase() {
        let meter = meter()
        let model = CircuitsModel()

        meter.update(viewer: Self.home + SIMD3(0, 0.3, 1), model: model)
        let front = meter.probeTip[.black]!
        meter.update(viewer: Self.home + SIMD3(1, 0.3, 0), model: model)
        let side = meter.probeTip[.black]!

        XCTAssertGreaterThan(
            simd_distance(front, side), 0.01,
            "a probe still in its holster did not turn with the meter")
        // Turning is not translating: measured from the anchor, since
        // `probeTip` is in the renderer's frame.
        XCTAssertEqual(simd_distance(front, meter.anchor),
                       simd_distance(side, meter.anchor), accuracy: 1e-4,
                       "the holstered probe changed its distance from the case")
    }

    // MARK: Mode

    /// Tapping the dial walks every mode and wraps.
    func testTappingTheDialCyclesEveryMode() throws {
        let meter = meter()
        let model = CircuitsModel()
        let dial = try XCTUnwrap(find("meter-dial", under: meter.root))
        let modes = CircuitsModel.MeterMode.allCases

        var seen: [CircuitsModel.MeterMode] = [model.meterMode]
        for _ in 1..<modes.count {
            XCTAssertTrue(meter.handleTap(dial, model: model),
                          "the dial refused a tap")
            seen.append(model.meterMode)
        }
        XCTAssertEqual(Set(seen).count, modes.count, "some mode is unreachable")

        meter.handleTap(dial, model: model)
        XCTAssertEqual(model.meterMode, seen[0], "the dial does not wrap")
    }

    /// The case and the probes do not steal the dial's tap.
    func testOnlyTheDialTakesTheTap() throws {
        let meter = meter()
        let model = CircuitsModel()
        for name in [Multimeter.bodyName, "meter-probe-red"] {
            let entity = try XCTUnwrap(find(name, under: meter.root))
            XCTAssertFalse(meter.handleTap(entity, model: model),
                           "\(name) consumed a tap meant for the bench")
        }
        XCTAssertEqual(model.meterMode, .voltsDC, "the mode changed anyway")
    }

    /// Every mode points the dial somewhere different — the guard for "the
    /// dial does nothing".
    func testEveryModePointsTheDialSomewhereDifferent() throws {
        let meter = meter()
        let model = CircuitsModel()
        let dial = try XCTUnwrap(find("meter-dial", under: meter.root))

        var angles: [Float] = []
        for _ in CircuitsModel.MeterMode.allCases {
            meter.update(viewer: nil, model: model)
            angles.append(dial.orientation.angle * dial.orientation.axis.z)
            meter.handleTap(dial, model: model)
        }

        for (i, a) in angles.enumerated() {
            for (j, b) in angles.enumerated() where j > i {
                XCTAssertGreaterThan(
                    abs(a - b), 0.2,
                    "modes \(i) and \(j) point the dial the same way")
            }
        }
    }

    /// The pointer stands proud of the moulded knob (z up to 0.0235 in the
    /// meter's frame), or turning the dial is a silent operation.
    func testThePointerClearsTheKnob() throws {
        let meter = meter()
        let dial = try XCTUnwrap(find("meter-dial", under: meter.root))
        let pointer = try XCTUnwrap(dial.children.first,
                                    "the dial has no pointer at all")
        XCTAssertGreaterThan(
            pointer.position.z, 0.005,
            "the pointer is buried inside the moulded knob — the dial will "
            + "turn and nothing will appear to happen")
    }
}
