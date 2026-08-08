//
//  GravityLabOrbitEditTests.swift
//  Physics Playground — app tests
//
//  The model half of "the orbit is the object": which bodies earn a ring,
//  what a bead drag writes back onto the system, and what happens at the
//  edges of the gesture. The MATH is pinned next door in
//  `PhysicsCoreTests/OrbitalElementsTests`; what is pinned here is the
//  wiring — display space in, sim state out, and a body that stays put
//  while the rest of the system keeps running.
//
//  Nothing here needs a simulator, and nothing here can pinch a bead. The
//  gesture itself is in `docs/ON_DEVICE_TESTS.md`, where it belongs.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class GravityLabOrbitEditTests: XCTestCase {

    private func earth(in model: GravityLabModel) -> GravityLabModel.OrbitingBody {
        model.bodies.first { $0.body.name == "Earth" }!
    }

    // MARK: Which bodies earn a ring

    func testEveryPlanetHasARingButTheSunDoesNot() {
        let model = GravityLabModel()
        let sun = model.primaryBody!
        XCTAssertNil(model.orbitFrame(for: sun.id),
                     "the primary is the focus, not a thing in orbit")
        for body in model.bodies where body.id != sun.id {
            XCTAssertNotNil(model.orbitFrame(for: body.id),
                            "\(body.body.name) has no orbit ring")
        }
    }

    /// A ring is a TWO-BODY statement, so it needs a body that dominates.
    /// Two equal suns is exactly the case where a planet's osculating
    /// ellipse about one of them describes nothing, and the ring going
    /// out is the scene saying so.
    func testTwinSunsExtinguishTheRing() {
        let model = GravityLabModel()
        let earthID = earth(in: model).id
        XCTAssertNotNil(model.orbitFrame(for: earthID))
        model.makeBinary()
        XCTAssertNil(model.orbitFrame(for: earthID),
                     "a ring survived the primary being split in half")
    }

    /// The ring reports the orbit the body is actually on. Earth's is
    /// nearly circular at 1 AU, and its period is a year.
    func testTheRingAgreesWithTheOrbitTheBodyIsOn() {
        let model = GravityLabModel()
        let elements = model.orbitElements(for: earth(in: model).id)!
        XCTAssertEqual(elements.semiMajorAxis! / CelestialBody.astronomicalUnit,
                       1, accuracy: 1e-6)
        XCTAssertEqual(elements.eccentricity, 0, accuracy: 1e-9)
        XCTAssertEqual(elements.period! / 86_400, 365.25, accuracy: 0.5)
        XCTAssertEqual(elements.kind, .ellipse)
    }

    // MARK: The drag

    func testDraggingTheFarBeadStretchesTheOrbit() {
        let model = GravityLabModel()
        let id = earth(in: model).id
        let before = model.orbitFrame(for: id)!
        XCTAssertTrue(model.beginOrbitEdit(bodyID: id, holding: .far))

        // Pull the far bead out to twice its radius, straight along the
        // apse line. Display space: the model converts.
        let target = -before.periapsisDirection * (before.apoapsisRadius * 2)
        model.dragApsis(toDisplayPoint: target * model.simToDisplay)

        let after = model.orbitFrame(for: id)!
        XCTAssertEqual(after.apoapsisRadius / (before.apoapsisRadius * 2), 1,
                       accuracy: 1e-9, "the far end did not follow the hand")
        XCTAssertEqual(after.periapsisRadius / before.periapsisRadius, 1,
                       accuracy: 1e-9, "the near end moved on its own")
        XCTAssertGreaterThan(after.eccentricity, before.eccentricity,
                             "stretching one end did not make it more eccentric")
    }

    /// The drag is expressed in DISPLAY space, and the renderer hands it
    /// a point that has already had the two-hand rig inverted out of it.
    /// So the same display point must mean the same orbit whatever the
    /// scale — if this ever fails, `displayPoint(fromWorld:)` has stopped
    /// undoing the rig and every bead drag is silently scale-dependent.
    func testTheDragIsIndependentOfTheViewScale() {
        func orbitAfterDrag() -> ApsisFrame {
            let model = GravityLabModel()
            let id = earth(in: model).id
            let start = model.orbitFrame(for: id)!
            model.beginOrbitEdit(bodyID: id, holding: .far)
            model.dragApsis(toDisplayPoint:
                -start.periapsisDirection * start.apoapsisRadius * 1.7
                * model.simToDisplay)
            return model.orbitFrame(for: id)!
        }
        let a = orbitAfterDrag(), b = orbitAfterDrag()
        XCTAssertEqual(a.apoapsisRadius, b.apoapsisRadius)
        XCTAssertEqual(a.periapsisRadius, b.periapsisRadius)
    }

    /// Lifting a bead out of the ecliptic tilts the whole orbit — the
    /// gesture that turns a flat solar system into a three-dimensional
    /// one without a single control for inclination.
    func testLiftingABeadTiltsTheOrbit() {
        let model = GravityLabModel()
        let id = earth(in: model).id
        let before = model.orbitFrame(for: id)!
        XCTAssertEqual(before.orbitNormal.y, 1, accuracy: 1e-9,
                       "Earth should start in the reference plane")

        model.beginOrbitEdit(bodyID: id, holding: .far)
        let tilt = 0.4
        let lifted = -before.periapsisDirection * cos(tilt)
            + before.orbitNormal * sin(tilt)
        model.dragApsis(toDisplayPoint:
            lifted * before.apoapsisRadius * model.simToDisplay)

        let after = model.orbitFrame(for: id)!
        let turned = acos(min(max(simd_dot(after.orbitNormal,
                                           before.orbitNormal), -1), 1))
        XCTAssertEqual(turned, tilt, accuracy: 1e-6,
                       "the orbit did not tilt with its bead")
        XCTAssertEqual(model.orbitElements(for: id)!.inclination, tilt,
                       accuracy: 1e-6)
    }

    // MARK: What the edit does to the rest of the system

    /// The edited body holds still while everything else keeps orbiting —
    /// the same contract `heldID` already carried for a grabbed body.
    func testTheEditedBodyIsFrozenWhileTheSystemRuns() {
        let model = GravityLabModel()
        let id = earth(in: model).id
        let marsID = model.bodies.first { $0.body.name == "Mars" }!.id
        model.beginOrbitEdit(bodyID: id, holding: .far)

        let earthBefore = model.bodies.first { $0.id == id }!.body.position
        let marsBefore = model.bodies.first { $0.id == marsID }!.body.position
        for _ in 0..<120 { model.step(dt: 1.0 / 90.0) }

        XCTAssertEqual(
            simd_distance(model.bodies.first { $0.id == id }!.body.position,
                          earthBefore), 0, accuracy: 1e-6,
            "the body being edited drifted out from under the hand")
        XCTAssertGreaterThan(
            simd_distance(model.bodies.first { $0.id == marsID }!.body.position,
                          marsBefore), 1e6,
            "the rest of the system stopped")
    }

    /// Letting go leaves the body on exactly the orbit the ring showed,
    /// and it stays on it.
    func testReleasingLeavesTheBodyOnTheOrbitItWasGiven() {
        let model = GravityLabModel()
        let id = earth(in: model).id
        let start = model.orbitFrame(for: id)!
        model.beginOrbitEdit(bodyID: id, holding: .far)
        model.dragApsis(toDisplayPoint:
            -start.periapsisDirection * start.apoapsisRadius * 1.8
            * model.simToDisplay)
        let authored = model.orbitElements(for: id)!
        model.endOrbitEdit()

        XCTAssertFalse(model.isEditingOrbit)
        XCTAssertNil(model.heldBodyID, "the body is still held after release")

        for _ in 0..<400 { model.step(dt: 1.0 / 90.0) }
        let after = model.orbitElements(for: id)!
        // Perturbed by the other planets, so not exact — but the same
        // orbit, which is the claim the ring makes.
        XCTAssertEqual(after.semiMajorAxis! / authored.semiMajorAxis!, 1,
                       accuracy: 0.02, "the authored orbit did not hold")
        XCTAssertEqual(after.eccentricity, authored.eccentricity, accuracy: 0.02)
    }

    func testReleasingClearsTheTrailThatDescribedTheOldOrbit() {
        let model = GravityLabModel()
        let id = earth(in: model).id
        for _ in 0..<200 { model.step(dt: 1.0 / 90.0) }
        XCTAssertFalse(model.bodies.first { $0.id == id }!.trail.isEmpty)

        model.beginOrbitEdit(bodyID: id, holding: .far)
        model.endOrbitEdit()
        XCTAssertTrue(model.bodies.first { $0.id == id }!.trail.isEmpty,
                      "the trail still describes an orbit that no longer exists")
    }

    // MARK: Edges

    func testTheFarBeadCannotBeGrabbedOnAnUnboundOrbit() {
        let model = GravityLabModel()
        let id = earth(in: model).id
        // Throw it hard enough to escape, WITHOUT moving it far: `hold`
        // teleports the body to the hand, so a big display displacement
        // would fling it several AU out and change the escape speed it
        // is being measured against. Earth sits at 0.5 display metres;
        // 5 cm of hand in 30 ms is 1.7 m/s, which the module's 8.6e4
        // scale turns into about 140 km/s against a 42 km/s escape.
        let start = SIMD3<Double>(0.5, 0, 0)
        model.grab(id: id, at: start, timestamp: 0)
        model.hold(id: id, at: start, timestamp: 0)
        model.hold(id: id, at: start + SIMD3(0, 0, -0.05), timestamp: 0.03)
        model.release(id: id, timestamp: 0.03)

        guard let frame = model.orbitFrame(for: id), !frame.hasApoapsis else {
            return XCTFail("the throw did not unbind the orbit")
        }
        XCTAssertFalse(model.beginOrbitEdit(bodyID: id, holding: .far),
                       "grabbed a far bead on an orbit that has no far end")
        XCTAssertTrue(model.beginOrbitEdit(bodyID: id, holding: .near),
                      "the near bead should still work on a hyperbola")
    }

    func testAnEditCannotStartWhereThereIsNoRing() {
        let model = GravityLabModel()
        XCTAssertFalse(
            model.beginOrbitEdit(bodyID: model.primaryBody!.id, holding: .near),
            "the Sun accepted an orbit edit")
    }

    /// Deleting the body under the hand must not leave the model holding
    /// a gesture on something that no longer exists.
    func testDeletingTheEditedBodyEndsTheEdit() {
        let model = GravityLabModel()
        let id = earth(in: model).id
        model.beginOrbitEdit(bodyID: id, holding: .far)
        model.removeBody(id: id)
        XCTAssertFalse(model.isEditingOrbit)
        XCTAssertNil(model.heldBodyID)
    }

    func testResetEndsAnyEditInFlight() {
        let model = GravityLabModel()
        model.beginOrbitEdit(bodyID: earth(in: model).id, holding: .far)
        model.reset()
        XCTAssertFalse(model.isEditingOrbit)
        XCTAssertNil(model.heldBodyID)
    }

    // MARK: The readout's one μ

    /// Semi-major axis, period and escape speed all used to be computed
    /// about slightly different two-body problems — GM in two places and
    /// G(M+m) in the third. Cross-check them against each other.
    func testTheReadoutUsesOneGravitationalParameter() {
        let model = GravityLabModel()
        let jupiter = model.bodies.first { $0.body.name == "Jupiter" }!
        let readout = model.readout(for: jupiter)!
        let elements = model.orbitElements(for: jupiter.id)!

        XCTAssertEqual(readout.periodDays! / (elements.period! / 86_400), 1,
                       accuracy: 1e-9,
                       "the readout's period and the ring's disagree")
        // v_esc = √2 × v_circ at the same radius, exactly.
        let circular = NBody.circularOrbitSpeed(
            centralMass: model.primaryBody!.body.mass + jupiter.body.mass,
            distance: readout.distanceAU * CelestialBody.astronomicalUnit,
            gravitationalConstant: model.effectiveG) / 1000
        XCTAssertEqual(readout.escapeSpeedKmPerS / circular, 2.0.squareRoot(),
                       accuracy: 1e-9)
    }

    // MARK: A body in the hand

    /// While a planet is held, `hold` has zeroed its velocity, so its
    /// osculating conic is a degenerate radial line. There is no honest
    /// ring to draw — the white prediction tube is the instrument for
    /// that moment, because it answers the question you are actually
    /// asking while holding something: what happens if I let go.
    func testAHeldBodyHasNoOrbitRing() {
        let model = GravityLabModel()
        let id = earth(in: model).id
        XCTAssertNotNil(model.orbitFrame(for: id))

        model.grab(id: id, at: SIMD3(0.5, 0, 0), timestamp: 0)
        model.hold(id: id, at: SIMD3(0.5, 0, 0), timestamp: 0)
        XCTAssertNil(model.orbitFrame(for: id),
                     "a ring was drawn around a body with no velocity")

        model.release(id: id, timestamp: 0.05)
        XCTAssertNil(model.heldBodyID)
    }

    /// …but an orbit EDIT is not a hold, even though it borrows `heldID`
    /// to keep the body still. The ring is the thing being manipulated,
    /// so it has to survive the gesture that manipulates it.
    func testAnOrbitEditKeepsItsRing() {
        let model = GravityLabModel()
        let id = earth(in: model).id
        XCTAssertTrue(model.beginOrbitEdit(bodyID: id, holding: .far))
        XCTAssertEqual(model.heldBodyID, id)
        XCTAssertNotNil(model.orbitFrame(for: id),
                        "the ring vanished during the drag that reshapes it")
        model.endOrbitEdit()
        XCTAssertNotNil(model.orbitFrame(for: id))
    }

    /// The physics the tap bug was masquerading as, pinned so nobody
    /// "fixes" it later: a body released at rest has no angular momentum
    /// and falls straight down its own radius into the primary. That is
    /// correct, and it is what the white prediction line draws.
    func testABodyReleasedAtRestFallsStraightIn() {
        let model = GravityLabModel()
        let id = earth(in: model).id
        let sun = model.primaryBody!.body.position
        let start = model.bodies.first { $0.id == id }!.body.position
        let bearing = simd_normalize(start - sun)

        model.grab(id: id, at: start * model.simToDisplay, timestamp: 0)
        model.hold(id: id, at: start * model.simToDisplay, timestamp: 0)
        model.release(id: id, timestamp: 0.05)

        for _ in 0..<400 { model.step(dt: 1.0 / 90.0) }
        let now = model.bodies.first { $0.id == id }!.body.position
        // Closer to the Sun...
        XCTAssertLessThan(simd_length(now - sun), simd_length(start - sun) * 0.99)
        // ...and still on the same ray out of it: a radial fall, not an orbit.
        XCTAssertEqual(simd_dot(simd_normalize(now - sun), bearing), 1,
                       accuracy: 1e-6,
                       "a body released at rest should fall straight in")
    }


    // MARK: Occlusion is measured in the ring's own frame

    /// A BEAD BURIED IN A PLANET MUST HIDE WHEREVER THE SYSTEM SITS.
    ///
    /// `OrbitRing.root` sits on the primary and places its beads
    /// relative to it, so occluders handed in ABSOLUTE display
    /// coordinates are offset from the beads by the primary's own
    /// position. `reset()` puts the Sun at exactly the origin, where the
    /// two frames coincide and the arithmetic is accidentally right —
    /// which is why this survived. Press "Twin suns" and the primaries
    /// go to ±0.2 AU: beads inside a planet stayed targetable, beads in
    /// open space were hidden and stripped of their input target.
    ///
    /// WHAT THIS TEST DOES AND DOES NOT COVER, said plainly because it
    /// looks like more than it is. `isOccluded` was always correct in
    /// isolation — it compares two points and two radii. The defect was
    /// at the CALL SITE, in `GravityLabRenderer.syncOrbitRing`, which
    /// built the occluder list in system coordinates and handed it to a
    /// function whose beads are in the ring's. That function is private
    /// and its renderer cannot be driven far enough from a test to reach
    /// it, so the fix itself is verified on device — see the Gravity Lab
    /// entry in `docs/ON_DEVICE_TESTS.md`.
    ///
    /// What this pins is the CONTRACT the call site now has to meet: the
    /// answer depends only on the relative arrangement, so anybody
    /// passing coordinates in the wrong frame is making a claim this
    /// spells out.
    func testOcclusionDoesNotDependOnWhereTheSystemSits() {
        let beadInRingFrame = SIMD3<Float>(0.30, 0, 0)
        let beadRadius: Float = 0.01

        // A planet sitting exactly on the bead, expressed in the ring's
        // frame — the same relative arrangement in both cases.
        let planetInRingFrame = (center: beadInRingFrame, radius: Float(0.05))

        for primary in [SIMD3<Float>.zero,
                        SIMD3<Float>(0.2, 0, 0),
                        SIMD3<Float>(-1.4, 0.3, 0.8)] {
            XCTAssertTrue(
                OrbitRing.isOccluded(bead: beadInRingFrame, radius: beadRadius,
                                     by: [planetInRingFrame]),
                "a bead inside a planet must hide with the primary at \(primary)")
        }

        // And a bead well clear of every body must stay visible.
        XCTAssertFalse(
            OrbitRing.isOccluded(bead: SIMD3(0.30, 0, 0), radius: beadRadius,
                                 by: [(center: SIMD3(-0.30, 0, 0), radius: 0.05)]),
            "a bead in open space was hidden")
    }
}
