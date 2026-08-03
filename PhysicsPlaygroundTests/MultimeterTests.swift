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
    func testAPlacedMeterSurvivesTheRenderLoop() {
        let meter = meter()
        let model = CircuitsModel()
        let moved = Self.home + SIMD3(0.35, -0.10, 0.20)

        meter.place(at: moved)
        for _ in 0..<12 {
            meter.update(viewer: SIMD3(0, 1.5, 0), model: model)
        }

        XCTAssertEqual(meter.anchor, moved)
        XCTAssertEqual(meter.root.position, moved,
                       "the render loop moved the meter back to where the "
                       + "view thought it should be")
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
