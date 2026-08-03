//
//  MultimeterTests.swift
//  Physics Playground — app tests
//
//  The bench meter, which spent a while being an instrument you could
//  neither move nor visibly operate.
//
//  Both failures were invisible from the code that appeared to implement
//  them, which is why they lasted:
//
//    • MOVE. The case carried a `GroundingShadowComponent` and nothing
//      else — no name, no collider, no input target — so there was
//      nothing for a drag to land on. And even with one, `update` wrote
//      `root.position` from a `private static let` every frame, so any
//      drag would have been erased before it drew.
//    • MODE. Tapping the dial really did advance `meterMode`, and always
//      had. But the pointer that shows which mode you are in sat four
//      millimetres INSIDE the mesh's knob, while the mesh carried a
//      second, static pointer moulded into the case. So the reading
//      changed, the dial did not appear to, and the control read as
//      broken.
//
//  Nothing automated can pinch a RealityKit entity, so these call the
//  handlers directly — the `StationTapTests` pattern. What they cannot
//  check is that a hand can reach the thing; what they CAN check is that
//  every precondition for a hand reaching it is in place.
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

    /// The collider is the CASE and not a comfortable box around it.
    /// This instrument stands among terminals a centimetre apart, and an
    /// oversized grab volume would shield the very things the probes are
    /// for.
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

    /// The case answers to `isBody`; the dial and the probes do not.
    /// The drag handler asks this question first, so a yes from the dial
    /// would mean the meter slid away instead of changing mode, and a
    /// yes from a probe would mean carrying a probe carried the meter.
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

    /// A placed meter STAYS placed across a frame.
    ///
    /// This is the whole of the move bug. `update` used to take the
    /// anchor as a parameter and write it unconditionally, from a
    /// constant the view owned — so the position was reset sixty times a
    /// second and a drag could never accumulate.
    ///
    /// It reads the CASE's world position, not `root.position`. `root`
    /// stopped moving on 2026-08-03 — it holds the case and the probes
    /// side by side and stays at the renderer's identity — so asserting
    /// on it would now pass whether or not a drag did anything.
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

    /// MOVING THE METER DOES NOT MOVE A PLACED PROBE.
    ///
    /// The second half of "these are separate objects". Turning the case
    /// was fixed first; dragging it dragged the measurement along for
    /// another round, because the probes still hung off the entity the
    /// anchor was written to.
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

    /// …and the lead still reaches, which is the thing that makes the
    /// separation legible rather than looking like a broken parent link.
    /// The lead is drawn jack-to-tip and scaled to span the gap, so its
    /// length is the assertion: move the case away and it must grow.
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

    /// A PLACED PROBE DOES NOT MOVE WHEN THE VIEWER DOES.
    ///
    /// The meter turns to face whoever is looking at it. The probes used
    /// to be children of the entity that turn was applied to, so walking
    /// round the bench swung a probe you had set on a terminal through
    /// the same arc as the case — while the reading, latched by terminal
    /// id rather than by position, went on claiming to measure there.
    ///
    /// A headset is the only thing that can walk round a bench, so this
    /// stands in for it the only way a test can: it walks the viewer a
    /// full circle and asks whether the probe stayed where it was put.
    ///
    /// IT ASKS THE ENTITY, NOT `probeTip`. The first draft of this test
    /// asserted on the stored tip and passed against the bug it was
    /// written to catch, because the stored tip is a coordinate in a
    /// frame that was itself being rotated — it never changed, and the
    /// probe moved anyway. What a wearer sees is the entity's place in
    /// the world, so that is what a test about a wearer must read.
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

    /// An UNTOUCHED probe still hangs off the instrument.
    ///
    /// The other half of the same decision: a probe nobody has picked up
    /// is in its holster, and a holster is part of the case. If this
    /// failed, turning the meter would leave two probes hanging in the
    /// air beside it, attached to their leads at one end and to nothing
    /// at the other.
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
        // Turning is not translating: it is still hanging off the case at
        // the same distance, on the other side. Measured FROM THE ANCHOR
        // — `probeTip` is in the renderer's frame, so its bare length is
        // a distance from the scene origin and would change under a
        // rotation that left the probe correctly holstered.
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

    /// Every mode points the dial somewhere DIFFERENT.
    ///
    /// The regression guard for "the dial does nothing": the mode can
    /// advance perfectly while the only thing that shows it never moves.
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

    /// And the pointer stands PROUD of the knob it rides on.
    ///
    /// The mesh's moulded knob occupies z ∈ [0.0155, 0.0235] in the
    /// meter's frame and the dial pivot sits at z = 0.0185, so a pointer
    /// authored at the pivot is swallowed whole. It has to clear 0.0235
    /// in world terms — 0.005 in the dial's own frame — or turning the
    /// dial is a silent operation.
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
